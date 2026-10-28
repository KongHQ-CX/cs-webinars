#!/usr/bin/env bash
# Stage 05 check on ready-1, with the failure switch at 50 percent. 200 requests through the gateway.
#   verify.sh          after the policy: fewer than 25 requests answer 503 (mean about 12)
#   verify.sh before   before the policy: more than 80 requests answer 503 (mean 100)
# Any status other than 200 or 503 fails either check.
#
# A proxy takes a moment to pick up a policy change. Before it samples, the script polls batches of
# 20 requests until the change shows (after: at most 3 of 20 answer 503; before: at least 6 of 20),
# discarding those batches, for up to WARMUP_BATCHES batches (default 30, 2 seconds apart).
#
# Prerequisites: stage 03 is in place, 10-failure-on.sh ran, and for the "after" check 05 apply.sh
# ran. Run on ready-1.
# Env: GATEWAY_URL (default: the gateway Service address).
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"
# shellcheck source=../../lib/gateway.sh
. "$WEBINAR_CODE_DIR/lib/gateway.sh"

mode="${1:-after}"
case "$mode" in before | after) ;; *) echo "usage: verify.sh [before]" >&2; exit 2 ;; esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
require_ctx_1 || exit 1
"$here/../02-app/verify-switch.sh" 50 "$(kubectl config current-context)"

url="$(gateway_url)" || exit 1

# Poll until the policy state shows, discarding the batches.
seen=0
for _ in $(seq 1 "${WARMUP_BATCHES:-30}"); do
  read -r _ok batch_fail _other <<<"$(count_requests "$url" 20)"
  if { [ "$mode" = "after" ] && [ "$batch_fail" -le 3 ]; } || { [ "$mode" = "before" ] && [ "$batch_fail" -ge 6 ]; }; then
    seen=1
    break
  fi
  sleep 2
done
[ "$seen" -eq 1 ] || { echo "FAIL: the policy state ($mode) did not show within ${WARMUP_BATCHES:-30} batches of 20 requests" >&2; exit 1; }

read -r ok fail other <<<"$(count_requests "$url" 200)"
echo "200 requests ($mode the policy): 200=$ok 503=$fail other=$other"
[ "$other" -eq 0 ] || { echo "FAIL: $other responses were neither 200 nor 503" >&2; exit 1; }

if [ "$mode" = "before" ]; then
  [ "$fail" -gt 80 ] || { echo "FAIL: expected more than 80 503s before the policy, got $fail" >&2; exit 1; }
else
  [ "$fail" -lt 25 ] || { echo "FAIL: expected fewer than 25 503s after the policy, got $fail" >&2; exit 1; }
  kubectl get meshretry demo-app-retry -n kong-mesh-system -o name >/dev/null || { echo "FAIL: MeshRetry demo-app-retry not found" >&2; exit 1; }
fi
echo "stage 05 OK ($mode)"
