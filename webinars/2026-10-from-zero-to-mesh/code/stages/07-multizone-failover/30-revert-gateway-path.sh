#!/usr/bin/env bash
# Stage 07: put the gateway path back to the stage 03 shape on the active context: the route goes to
# the demo Service again and the gateway loses the MeshMultiZoneService reachable backend.
# Does nothing on a context with no gateway (zone 2). cleanup.sh calls it, so it is safe to repeat.
#
# Prerequisites: none beyond a reachable cluster. Safe on any ready-* context.
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"
# shellcheck source=../../lib/gateway.sh
. "$WEBINAR_CODE_DIR/lib/gateway.sh"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gw_dir="$here/../03-gateway"
gw_ns="kong"

if ! kubectl get gateway demo-gateway -n "$gw_ns" -o name >/dev/null 2>&1; then
  echo "no gateway on $(kubectl config current-context), nothing to revert"
  exit 0
fi

before="$(gateway_observed_generation "$gw_ns")"
kubectl apply -f "$gw_dir/50-httproute.yaml"
kubectl apply -f "$gw_dir/40-gateway.yaml"
# The annotation change rolls the gateway pods. Wait for a new observedGeneration, then the rollout.
wait_gateway_rollout "$gw_ns" "$before"
echo "gateway path reverted on $(kubectl config current-context)"
