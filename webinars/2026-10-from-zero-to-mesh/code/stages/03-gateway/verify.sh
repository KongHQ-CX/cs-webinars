#!/usr/bin/env bash
# Stage 03 check on ready-1: the Gateway is Programmed, gateway pods have the sidecar, the gateway
# Service carries the delegated gateway annotations, every LoadBalancer Service has
# externalTrafficPolicy Local, no NetworkPolicy of ours admits the world, GET / returns 200 through the
# gateway, and nothing under /admin is routed.
# This check does not prove who can reach the gateway. The edge control is the load balancer firewall
# rule pair (allow your own /32, deny the rest), proved by the port check of the infrastructure
# step and by a request from a second address. The Operator also makes its own open NetworkPolicy for
# the gateway pods, so a NetworkPolicy cannot narrow access.
# A fresh stage 03 without the demo-gateway-tls Secret has not been tried (every live run had the Secret
# first), so run the certs step before it. The HTTPS listener check below only warns.
# The failure switch must read 0 (stage 03 comes before the planted failure).
#
# Prerequisites: stage 03 apply.sh ran on ready-1. Env: GATEWAY_URL (default: the gateway Service address).
# With EDGE_CONTROL_ACK=1 every LoadBalancer Service must be Local. Without it no Service may be a
# LoadBalancer or NodePort, and GATEWAY_URL must be set (for example a port-forward).
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"
# shellcheck source=../../lib/gateway.sh
. "$WEBINAR_CODE_DIR/lib/gateway.sh"

ns="kong"
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }

require_ctx_1 || exit 1
ctx="$(kubectl config current-context)"

# 1. Every pod in the gateway namespace is Ready and has the kuma-sidecar container.
kubectl wait --for=condition=Ready pod --all -n "$ns" --timeout=120s >/dev/null || bad "gateway pods not ready"
has_sidecar "$ns" || bad "a pod in $ns has no kuma-sidecar (restart it after the namespace label and the zone control plane exist)"

# 1b. The Gateway is Programmed.
[ "$(kubectl get gateway demo-gateway -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')" = "True" ] ||
  bad "gateway demo-gateway is not Programmed"

# 1c. The HTTPS listener resolves its certificate Secret. A warning only: the HTTP listener serves
# without it, and the certificate step can run later. ResolvedRefs False means demo-gateway-tls is
# missing or not labelled for the Operator.
refs="$(kubectl get gateway demo-gateway -n "$ns" -o jsonpath='{.status.listeners[?(@.name=="https")].conditions[?(@.type=="ResolvedRefs")].status}' 2>/dev/null || true)"
if [ "$refs" = "False" ]; then
  echo "warning: the HTTPS listener has ResolvedRefs False: the Secret demo-gateway-tls is missing or not labelled. HTTP still works. Run the certs step (just up-from certs)." >&2
fi

# 2. The ingress Service: annotations. Every LoadBalancer Service keeps the client address.
svc_json="$(kubectl get svc -n "$ns" -l gateway-operator.konghq.com/dataplane-service-type=ingress -o json)"
[ "$(jq '.items | length' <<<"$svc_json")" -ge 1 ] || bad "no ingress Service in $ns"
jq -e 'all(.items[]; .metadata.annotations["kuma.io/ignore"] == "true")' <<<"$svc_json" >/dev/null || bad "ingress Service lacks kuma.io/ignore: \"true\""
if [ "${EDGE_CONTROL_ACK:-}" = "1" ]; then
  gateway_svc_local "$ns" || bad "a LoadBalancer Service in $ns does not have externalTrafficPolicy $GATEWAY_TRAFFIC_POLICY (or none exists)"
else
  gateway_svc_internal "$ns" || bad "a LoadBalancer or NodePort Service exists in $ns but EDGE_CONTROL_ACK is not 1"
fi

# 3. The gateway pod keeps its inbound ports out of the sidecar, and no policy of ours opens them to the world.
pod_json="$(kubectl get pods -n "$ns" -o json)"
jq -e '[.items[] | select(.metadata.annotations["traffic.kuma.io/exclude-inbound-ports"] != null)] | length >= 1' <<<"$pod_json" >/dev/null ||
  bad "no gateway pod carries traffic.kuma.io/exclude-inbound-ports"
gateway_no_world_policy "$ns" || bad "a NetworkPolicy in $ns that is not the Operator's admits every source"

# 4. Through the gateway: GET / is 200 (poll up to 60 seconds for the route to reach the gateway).
url="$(gateway_url)" || exit 1
got=""
for _ in $(seq 1 30); do
  got="$(request_once "$url")"
  [ "${got%% *}" = "200" ] && break
  sleep 2
done
# Before stage 00 there is no MeshTrafficPermission, so the mesh denies the gateway's call into the
# mesh: the sidecar answers 403 "RBAC: access denied". Stage 00 needs the running gateway to read its
# SPIFFE ID, so it must come after this stage. Accept exactly that denial while no MeshTrafficPermission
# exists, and say so. Once one exists, require 200 (seen on the first live run, 2026-10-19).
if [ "${got%% *}" != "200" ]; then
  mtp_count="$(kubectl get meshtrafficpermissions -A -o name 2>/dev/null | wc -l | tr -d ' ')"
  deny_body="$(curl -s -m 5 "$url/" 2>/dev/null || true)"
  if [ "${got%% *}" = "403" ] && [ "${mtp_count:-0}" = "0" ] && [ "$deny_body" = "RBAC: access denied" ]; then
    echo "note: GET / returned 403 RBAC: access denied. Expected until stage 00 adds the allow rule; run this check again after stage 00 and it must read 200."
  else
    bad "GET / through the gateway returned '${got%% *}', expected 200"
  fi
fi

# 5. /admin is not routed: GET and POST give 404 or 405.
for method in GET POST; do
  code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X "$method" "$url/admin/failure" || echo 000)"
  case "$code" in 404 | 405) ;; *) bad "$method /admin/failure through the gateway returned $code, expected 404 or 405" ;; esac
done

[ "$fail" -eq 0 ] || exit 1
echo "stage 03 OK on $ctx"
echo "this proves the allow side only. The edge control is the load balancer firewall: run its port check, then request from a second address (expect a timeout)."
