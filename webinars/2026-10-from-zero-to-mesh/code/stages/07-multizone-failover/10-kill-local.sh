#!/usr/bin/env bash
# Stage 07: remove the demo app from the caller's zone by scaling its Deployment to 0 on the active
# context (ready-1). 20-restore-local.sh brings the pods back.
#
# Prerequisites: stage 07 apply.sh ran and the active context is ready-1 (the zone with the gateway).
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

require_ctx_1 || exit 2
ns="${DEMO_NAMESPACE:-demo}"
kubectl scale deployment/demo-app -n "$ns" --replicas=0
kubectl wait --for=delete pod -l app=demo-app -n "$ns" --timeout=120s
echo "demo-app has 0 pods on $(kubectl config current-context)"
