#!/usr/bin/env bash
# Install a Kong Mesh zone control plane and its mesh-scoped zone proxies with Helm.
# Usage: install-zone.sh <install|ready> <zone-name>
#
# Create the zone token Secret first (fill-from-env.sh zone). The script then needs:
#   KONNECT_CP_ID        mesh control plane id
#   KDS_GLOBAL_ADDRESS   grpcs://<region>.mesh.sync.konghq.com:443 (host must end in .mesh.sync.konghq.com)
#   MESH_NAME            the mesh the zone proxies belong to
#   PEER_NAT_IPS         comma-separated /32 list allowed to reach the zone ingress
# On one cluster set SINGLE_CLUSTER=true and ALLOWED_SOURCE_RANGES (a /32 list, your own
# address) instead of PEER_NAT_IPS. The zone ingress is never open to the world.
# Optional: CHART_VERSION (default 2.14.6).
# Needs helm, kubectl, jq and yq (mikefarah, v4).
#
# The script fails closed on the source range. Before it installs, it renders the chart with
# helm template and refuses to go on unless every LoadBalancer Service (ingress and egress)
# carries exactly the allowed ranges. After the install it reads the live Services and
# compares again. On a mismatch it uninstalls the release.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$here/../lib/common.sh"

CHART_REPO="https://kong.github.io/kong-mesh-charts"
usage="usage: install-zone.sh <install|ready> <zone-name>"
[ "$#" -eq 2 ] || { echo "$usage" >&2; exit 2; }
set_name="$1"
zone="$2"
case "$set_name" in install | ready) ;; *) echo "$usage" >&2; exit 2 ;; esac
[[ $zone =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { _err "zone name must be lowercase letters, digits and hyphens"; exit 2; }

if [ "${SINGLE_CLUSTER:-}" = "true" ]; then
  require_vars KONNECT_CP_ID KDS_GLOBAL_ADDRESS MESH_NAME ALLOWED_SOURCE_RANGES
  ranges="$ALLOWED_SOURCE_RANGES"
else
  require_vars KONNECT_CP_ID KDS_GLOBAL_ADDRESS MESH_NAME PEER_NAT_IPS
  ranges="$PEER_NAT_IPS"
fi
require_cidr32_list "$ranges"
[[ $KONNECT_CP_ID =~ ^[A-Za-z0-9-]+$ ]] || { _err "KONNECT_CP_ID has unexpected characters"; exit 2; }
[[ $KDS_GLOBAL_ADDRESS =~ ^grpcs://([a-z0-9-]+\.)+mesh\.sync\.konghq\.com(:[0-9]+)?$ ]] || { _err "KDS_GLOBAL_ADDRESS must look like grpcs://<region>.mesh.sync.konghq.com:443"; exit 2; }
[[ $MESH_NAME =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { _err "MESH_NAME must be lowercase letters, digits and hyphens"; exit 2; }
# DNS-1123: a label for the namespace, a subdomain for the Secret name.
[[ $ZONE_SECRET_NAMESPACE =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { _err "ZONE_SECRET_NAMESPACE must be a DNS-1123 label"; exit 2; }
{ [ "${#ZONE_SECRET_NAME}" -le 253 ] && [[ $ZONE_SECRET_NAME =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; } || { _err "ZONE_SECRET_NAME must be a DNS-1123 name"; exit 2; }
[[ $SECRET_KEY =~ ^[A-Za-z0-9._-]+$ ]] || { _err "SECRET_KEY has unexpected characters"; exit 2; }
chart_version="${CHART_VERSION:-2.14.6}"
[[ $chart_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { _err "CHART_VERSION must look like 2.14.6"; exit 2; }
for tool in helm kubectl jq yq; do
  command -v "$tool" >/dev/null 2>&1 || { _err "$tool is required and was not found on PATH"; exit 2; }
done

require_ctx "$set_name"

if [ "${SINGLE_CLUSTER:-}" = "true" ]; then
  printf 'warning: SINGLE_CLUSTER=true. Only %s can reach the zone ingress, so a second cluster is refused\n' "$ranges" >&2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; rm -f "${PINNED_KUBECONFIG:-}"' EXIT
# Pin a private kubeconfig to this context, so a context switch in another terminal cannot
# send the install, the check or the rollback to a different cluster.
ctx_now="$(kubectl config current-context)"
pin_kubeconfig "$ctx_now" || exit 1
# Every substituted value is validated above, so none holds a character that sed treats specially.
range_list="[\"${ranges//,/\", \"}\"]"
sed -e "s|\${ZONE_NAME}|$zone|g" \
  -e "s|\${KDS_GLOBAL_ADDRESS}|$KDS_GLOBAL_ADDRESS|g" \
  -e "s|\${KONNECT_CP_ID}|$KONNECT_CP_ID|g" \
  -e "s|\${ZONE_SECRET_NAME}|$ZONE_SECRET_NAME|g" \
  -e "s|\${SECRET_KEY}|$SECRET_KEY|g" \
  -e "s|\${MESH_NAME}|$MESH_NAME|g" \
  -e "s|\${SOURCE_RANGES}|$range_list|g" \
  "$here/../helm/install-zone.values.yaml" >"$tmp/values.yaml"

# Sorted JSON array of the allowed ranges, to compare with what Kubernetes holds.
want="$(jq -cn --arg r "$ranges" '$r | split(",") | sort')"

# lb_ranges_ok <json-lines-of-services>: every LoadBalancer Service carries exactly $want, and one exists.
lb_ranges_ok() {
  jq -s -e --argjson want "$want" '
    [.[] | select(.kind == "Service" and .spec.type == "LoadBalancer")] as $lb
    | ($lb | length) > 0
      and all($lb[]; ((.spec.loadBalancerSourceRanges // []) | sort) == $want)' >/dev/null
}

helm template kong-mesh kong-mesh --repo "$CHART_REPO" --version "$chart_version" \
  --namespace "$ZONE_SECRET_NAMESPACE" -f "$tmp/values.yaml" >"$tmp/rendered.yaml" ||
  { _err "helm template failed, nothing installed"; exit 1; }
yq eval-all -o=json -I=0 'select(.kind == "Service")' "$tmp/rendered.yaml" >"$tmp/services.jsonl" ||
  { _err "cannot read the rendered Services, nothing installed"; exit 1; }
lb_ranges_ok <"$tmp/services.jsonl" || {
  _err "the chart renders no LoadBalancer Service, or one without exactly the allowed source ranges. Nothing installed"
  exit 1
}

kubectl create namespace "$ZONE_SECRET_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
helm upgrade --install kong-mesh kong-mesh --repo "$CHART_REPO" --version "$chart_version" \
  --namespace "$ZONE_SECRET_NAMESPACE" -f "$tmp/values.yaml" --wait --timeout 5m --kube-context "$ctx_now"

# Compare the live Services with the allowed ranges. Remove the release on a mismatch.
if ! kubectl get svc -n "$ZONE_SECRET_NAMESPACE" -o json | jq -c '.items[]' | lb_ranges_ok; then
  _err "a live LoadBalancer Service does not carry exactly the allowed source ranges, uninstalling"
  helm uninstall kong-mesh -n "$ZONE_SECRET_NAMESPACE" --kube-context "$ctx_now" || _err "helm uninstall failed, remove the release by hand"
  exit 1
fi

wait_pods "$ZONE_SECRET_NAMESPACE" "app=kong-mesh-control-plane"
echo "zone $zone installed in $(kubectl config current-context)"
