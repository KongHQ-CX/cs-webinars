#!/usr/bin/env bash
# Stage 02 check on the active kubectl context: pods ready, sidecar on every pod, failure switch at 0 on every pod.
# It does not curl the gateway: the gateway does not exist yet (stage 03 verifies that).
#
# Prerequisites: stage 02 apply.sh ran on this context (a ready context).
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/../../lib/common.sh"

require_ctx ready || exit 1

ns="${DEMO_NAMESPACE:-demo}"
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }

kubectl -n "$ns" wait --for=condition=Ready pod -l app=demo-app --timeout=120s >/dev/null || bad "pods not ready"

pods="$(kubectl -n "$ns" get pods -l app=demo-app -o name)"
[ -n "$pods" ] || { echo "FAIL: no demo pods" >&2; exit 1; }

while IFS= read -r pod; do
  name="${pod#pod/}"
  containers="$(kubectl -n "$ns" get pod "$name" -o jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}')"
  # kuma-sidecar is the injected container name. Without it the pod started before the namespace label.
  case " $containers " in
    *" kuma-sidecar "*) ;;
    *) bad "$name has no kuma-sidecar container (restart it after the namespace label and the zone control plane exist)" ;;
  esac
  got="$(kubectl -n "$ns" exec "$name" -c demo-app -- python3 /app/adminctl.py get 2>/dev/null || echo error)"
  [ "$got" = "0" ] || bad "$name failure switch reads '$got', expected 0"
done <<< "$pods"

[ "$fail" -eq 0 ] || exit 1
echo "stage 02 OK on $(kubectl config current-context)"
