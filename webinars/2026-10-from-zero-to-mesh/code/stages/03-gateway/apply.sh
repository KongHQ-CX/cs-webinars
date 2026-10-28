#!/usr/bin/env bash
# Stage 03: the gateway in zone 1 (Kong Operator, delegated gateway with a sidecar) and its one route.
#
# Prerequisites: the Operator is installed (bin/install-operator.sh), its token Secret exists in
# namespace kong (OPERATOR_SECRET_NAMESPACE=kong bin/fill-from-env.sh operator), the zone control
# plane runs, the active context is ready-1 (the gateway runs in zone 1 only), and python3 and yq
# are installed (the offline schema check).
#
# Env (all required):
#   MESH_NAME           mesh name, lowercase letters, digits and hyphens.
#   GATEWAY_CP_ID       ID of the existing Konnect gateway control plane (a UUID).
#   KONNECT_SERVER_URL  Konnect API hostname for your geo: us, eu, au, me or in, for example us.api.konghq.com.
#   GATEWAY_IMAGE       Kong Gateway image as name:tag@sha256:<64 hex>, tag pinned to a patch version,
#                       for example kong/kong-gateway:3.15.0.0@sha256:<digest>.
# Optional: EDGE_CONTROL_ACK=1 says a firewall (or an equivalent edge control) that admits only the
#             your own address is already in place on the load balancer. Only the value 1 counts.
#             With it the ingress Service is a LoadBalancer. Without it the ingress Service is a
#             ClusterIP, so nothing is exposed outside the cluster (reach the gateway with a port-forward
#             and set GATEWAY_URL for verify.sh).
#           SERVICE_UPSTREAM=0 skips the Service annotation,
#           RENDER_ONLY=1 prints the filled manifests and applies nothing (no cluster needed).
#
# Who can reach the gateway: the GatewayConfiguration has no source range field, and a NetworkPolicy
# cannot narrow the gateway (the Operator makes its own open policy for the gateway pods and policies
# add up). The edge control is the firewall rule pair on the load balancer, set outside this script.
# With EDGE_CONTROL_ACK=1 the Service keeps the client address (externalTrafficPolicy, see
# GATEWAY_TRAFFIC_POLICY in lib/gateway.sh) so the firewall can see who is calling.
#
# Order: refusals, the offline schema check of the stage 03 manifests, the namespace, then a
# server-side dry run of every manifest, all before the rest is created. Then the GatewayConfiguration,
# read back before the Gateway exists.
# Fail closed: after the Gateway is Programmed the script reads the live Service and the policies in
# the namespace again. A trap deletes the Gateway when this run created it and stops early, and on a
# rerun it deletes the Gateway only when a read-back proves the edge is wrong (the configuration, the
# live Service or a world-open policy). Other failures on a rerun leave the serving Gateway alone.
# The route is applied last, only after those checks pass. Every kubectl call uses the context
# captured at the start, so a context switch mid-run cannot redirect the delete.
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"
# shellcheck source=../../lib/gateway.sh
. "$WEBINAR_CODE_DIR/lib/gateway.sh"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ns="kong"

require_vars MESH_NAME GATEWAY_CP_ID KONNECT_SERVER_URL GATEWAY_IMAGE || exit 2
[[ "$MESH_NAME" =~ ^[a-z0-9-]+$ ]] || { _err "MESH_NAME must be lowercase letters, digits and hyphens"; exit 2; }
[[ "$GATEWAY_CP_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || { _err "GATEWAY_CP_ID must be a UUID"; exit 2; }
[[ "$KONNECT_SERVER_URL" =~ ^(us|eu|au|me|in)\.api\.konghq\.com$ ]] || { _err "KONNECT_SERVER_URL must be <geo>.api.konghq.com with geo us, eu, au, me or in"; exit 2; }
[[ "$GATEWAY_IMAGE" =~ ^[a-z0-9./_-]+:[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)*@sha256:[0-9a-f]{64}$ ]] || { _err "GATEWAY_IMAGE must be name:tag@sha256:<64 hex> with the tag pinned to a patch version, for example kong/kong-gateway:3.15.0.0@sha256:<digest>"; exit 2; }

# Only the value 1 exposes the gateway. Anything else keeps it inside the cluster.
if [ "${EDGE_CONTROL_ACK:-}" = "1" ]; then
  INGRESS_TYPE="LoadBalancer"
else
  INGRESS_TYPE="ClusterIP"
fi

render() { # files to fill, default all numbered files
  local f files=("$@")
  [ "${#files[@]}" -gt 0 ] || files=("$here"/[0-9][0-9]-*.yaml)
  for f in "${files[@]}"; do
    echo "---"
    sed -e "s|\${MESH_NAME}|$MESH_NAME|g" \
      -e "s|\${GATEWAY_CP_ID}|$GATEWAY_CP_ID|g" \
      -e "s|\${KONNECT_SERVER_URL}|$KONNECT_SERVER_URL|g" \
      -e "s|\${GATEWAY_IMAGE}|$GATEWAY_IMAGE|g" \
      -e "s|\${INGRESS_TYPE}|$INGRESS_TYPE|g" "$f" |
      if [ "$INGRESS_TYPE" = "ClusterIP" ] && [ "$(basename "$f")" = "20-gatewayconfiguration.yaml" ]; then
        # The CRD rejects externalTrafficPolicy on a ClusterIP Service.
        grep -v '^          externalTrafficPolicy:'
      else
        cat
      fi
  done
}

if [ "${RENDER_ONLY:-0}" = "1" ]; then
  render
  exit 0
fi

require_ctx_1 || exit 2
ctx="$(command kubectl config current-context)"
# Pin every later kubectl call (this script and the lib helpers) to the captured context.
kubectl() { command kubectl --context "$ctx" "$@"; }
apply() { kubectl apply --validate=strict -f -; }

# Before anything is created, every manifest is checked, so a typo cannot leave half a gateway.
# The checks: the schema checker (offline, against the Operator's field list), then the API server's dry run.
for tool in python3 yq; do
  command -v "$tool" >/dev/null 2>&1 || { _err "$tool is not installed: the offline schema check needs python3 and yq. Nothing created"; exit 1; }
done
python3 -I "$WEBINAR_CODE_DIR/lib/manifests_check.py" --stage "$here" ||
  { _err "the schema checker rejects the stage 03 manifests (output above). Nothing created"; exit 1; }

# Cleanup. created_by_us: this run applied the Gateway object. edge_wrong: a read-back proved the edge
# is wrong, so the Gateway goes even when an earlier run created it.
created_by_us=0
edge_wrong=0
finished=0
cleanup() {
  local rc=$?
  if [ "$finished" -eq 0 ] && { [ "$created_by_us" -eq 1 ] || [ "$edge_wrong" -eq 1 ]; }; then
    _err "run did not finish (exit $rc), deleting the Gateway"
    kubectl delete gateway demo-gateway -n "$ns" --ignore-not-found >&2 ||
      _err "delete the Gateway by hand: kubectl delete gateway demo-gateway -n $ns"
  fi
  return "$rc"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
# edge_fail <message>: a read-back proved the edge is wrong. Delete the Gateway and stop.
edge_fail() { _err "$1"; edge_wrong=1; exit 1; }

# A rerun finds the Gateway already there. Then only an edge read-back failure deletes it.
existing="$(kubectl get gateway demo-gateway -n "$ns" --ignore-not-found -o name)" ||
  { _err "cannot read gateway/demo-gateway in $ns, nothing applied"; exit 1; }

if [ "$INGRESS_TYPE" = "ClusterIP" ]; then
  echo "EDGE_CONTROL_ACK is not 1: the ingress Service will be a ClusterIP and the gateway stays closed to the outside."
  echo "Put the load balancer firewall in place, then rerun with EDGE_CONTROL_ACK=1 to expose it."
fi

# Namespace first, so the sidecar label exists before any pod starts and the dry run can check
# namespaced objects.
render "$here/00-namespace.yaml" | apply
render | kubectl apply --dry-run=server --validate=strict -f - >/dev/null ||
  { _err "the API server rejects a manifest in a dry run. Nothing else created"; exit 1; }

# The auth object reads the token from the Secret in this namespace. Wait for the Operator to call
# Konnect with it; a missing or wrong token stops the stage here, before any gateway exists.
render "$here/10-konnectapiauth.yaml" | apply
kubectl wait --for=condition=APIAuthValid konnectapiauthconfiguration/konnect-api-auth -n "$ns" --timeout=60s ||
  { _err "Konnect auth is not valid: fill the token first (OPERATOR_SECRET_NAMESPACE=$ns bin/fill-from-env.sh operator) and check the Operator runs"; exit 1; }

# Order matters: the configuration exists before the Gateway creates the Service.
render "$here/20-gatewayconfiguration.yaml" | apply
gwc_path='{.spec.dataPlaneOptions.network.services.ingress'
ing_type="$(kubectl get gatewayconfiguration demo-gateway-config -n "$ns" -o jsonpath="$gwc_path.type}")" ||
  { _err "cannot read the GatewayConfiguration back, no Gateway applied"; exit 1; }
[ "$ing_type" = "$INGRESS_TYPE" ] ||
  edge_fail "the GatewayConfiguration holds ingress type '$ing_type', expected $INGRESS_TYPE. No Gateway applied"
if [ "$INGRESS_TYPE" = "LoadBalancer" ]; then
  policy="$(kubectl get gatewayconfiguration demo-gateway-config -n "$ns" -o jsonpath="$gwc_path.externalTrafficPolicy}")" ||
    { _err "cannot read the GatewayConfiguration back, no Gateway applied"; exit 1; }
  [ "$policy" = "$GATEWAY_TRAFFIC_POLICY" ] ||
    edge_fail "the GatewayConfiguration holds externalTrafficPolicy '$policy', expected $GATEWAY_TRAFFIC_POLICY. No Gateway applied"
fi
render "$here/30-gatewayclass.yaml" | apply
[ -n "$existing" ] || created_by_us=1
render "$here/40-gateway.yaml" | apply

kubectl wait --for=condition=Programmed gateway/demo-gateway -n "$ns" --timeout=300s ||
  { _err "the Gateway is not Programmed"; exit 1; }
# The Service appears once the Gateway is Programmed. Wait for it, then read the live objects back.
if [ "$INGRESS_TYPE" = "LoadBalancer" ]; then
  for _ in $(seq 1 30); do
    [ "$(kubectl get svc -n "$ns" -o json | jq '[.items[] | select(.spec.type == "LoadBalancer")] | length')" -gt 0 ] && break
    sleep 2
  done
  gateway_svc_local "$ns" ||
    edge_fail "a LoadBalancer Service in $ns does not have externalTrafficPolicy $GATEWAY_TRAFFIC_POLICY (or none exists). Deleting the Gateway"
else
  gateway_svc_internal "$ns" ||
    edge_fail "a LoadBalancer or NodePort Service exists in $ns without EDGE_CONTROL_ACK=1. Deleting the Gateway"
fi
gateway_no_world_policy "$ns" ||
  edge_fail "a NetworkPolicy in $ns that is not the Operator's admits every source. Deleting the Gateway"
wait_pods "$ns" "" || { _err "pods in $ns are not Ready"; exit 1; }

# The checks passed: now the Service annotation that makes the gateway call the Service name, and the route.
if [ "${SERVICE_UPSTREAM:-1}" = "1" ]; then
  kubectl patch service demo-app -n "${DEMO_NAMESPACE:-demo}" --type merge --patch-file "$here/service-upstream.patch.yaml"
fi
render "$here/50-httproute.yaml" | apply

finished=1
echo "stage 03 applied to $ctx"
echo "who can reach the gateway is the load balancer firewall, not this stage: run its check from your own machine, then a request from a second address must time out"
