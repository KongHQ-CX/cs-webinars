#!/usr/bin/env bash
# Stage 07: send the gateway's traffic to the MeshMultiZoneService (draft path, see the files in patches/).
# 1. Failure switch to 0 in both zones: a leftover 50 percent would break the all-200 checks.
# 2. Check the MeshMultiZoneService exists (the global control plane owns it, nothing here creates it).
# 3. Apply the ExternalName Service, the gateway with one more reachable backend, and the route.
# Run on ready-1, where the gateway is. Env: CTX_1 (default ready-1), CTX_2 (default ready-2).
#
# Prerequisites: stages 00 to 03 are in place, the MeshMultiZoneService demo-app exists (applied on
# the global control plane), and the active context is ready-1.
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"
# shellcheck source=../../lib/gateway.sh
. "$WEBINAR_CODE_DIR/lib/gateway.sh"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ctx1="${CTX_1:-ready-1}"
ctx2="${CTX_2:-ready-2}"

require_ctx_1 || exit 2

for ctx in "$ctx1" "$ctx2"; do
  KUBECTL_CONTEXT="$ctx" "$WEBINAR_CODE_DIR/bin/set-failure.sh" 0
done

# Select by display name, not by object name: the zone copy gets a hash suffix on its name
# (smw-ready-demo-app-b48vwz92fc9f7w6z on 2026-10-19), and the display name is the annotation
# kuma.io/display-name, not a label.
mzsvc="$(kubectl get meshmultizoneservice -n kong-mesh-system -o json |
  jq -r '.items[] | select(.metadata.annotations["kuma.io/display-name"] == "demo-app") | "meshmultizoneservice/" + .metadata.name')"
[ -n "$mzsvc" ] ||
  { _err "no MeshMultiZoneService with display name demo-app: the global control plane owns it, apply it there first (see shown/meshmultizoneservice.yaml)"; exit 1; }

before="$(gateway_observed_generation kong)"
kubectl apply -f "$here/20-externalname-service.yaml"
kubectl apply -f "$here/patches/40-gateway-mzsvc.yaml"
kubectl apply -f "$here/patches/50-httproute-mzsvc.yaml"
# The annotation change rolls the gateway pods. A Deployment that is already Available says nothing
# about that, so wait for a new observedGeneration, then for the rollout, sidecar included.
wait_gateway_rollout kong "$before"
echo "stage 07 applied to $ctx1"
