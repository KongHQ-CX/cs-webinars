#!/usr/bin/env bash
# Stage 07 check on ready-1, through the gateway. The failure switch must read 0.
#   verify.sh            all pods up: 100 requests, all 200, all answered by LOCAL_ZONE
#   verify.sh killed     after 10-kill-local.sh: 100 requests, all 200, none answered by LOCAL_ZONE
#                        (polls up to 90 seconds for the mesh to stop sending to the dead zone)
#   verify.sh restored   after 20-restore-local.sh: back to the "all pods up" check, switch reads 0 in both zones
# Env: LOCAL_ZONE (the zone name ready-1 reports, default ZONE_NAME), REMOTE_ZONE (required, the zone
#      name ready-2 reports), GATEWAY_URL (default: the gateway Service address), CTX_1 (default
#      ready-1), CTX_2 (default ready-2), WARM_CONSECUTIVE (default 15) and WARM_TIMEOUT (default 90
#      seconds) for the gateway warm-up wait, which runs in the "up" mode only, before the 100 requests.
#
# Prerequisites: stage 07 apply.sh ran on ready-1 and demo pods run in both zones.
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"
# shellcheck source=../../lib/gateway.sh
. "$WEBINAR_CODE_DIR/lib/gateway.sh"

mode="${1:-up}"
case "$mode" in up | killed | restored) ;; *) echo "usage: verify.sh [killed|restored]" >&2; exit 2 ;; esac
LOCAL_ZONE="${LOCAL_ZONE:-${ZONE_NAME:-}}"
require_vars LOCAL_ZONE REMOTE_ZONE || exit 2
[ "$LOCAL_ZONE" != "$REMOTE_ZONE" ] || { _err "LOCAL_ZONE and REMOTE_ZONE are both '$LOCAL_ZONE': they must name different zones"; exit 2; }
require_ctx_1 || exit 2

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ctx1="${CTX_1:-ready-1}"
ctx2="${CTX_2:-ready-2}"
url="$(gateway_url)" || exit 1

# sample <n>: prints "<non-200 count> <local-zone count> <other-zone count>".
sample() {
  local n="$1" line bad=0 local_n=0 other_n=0 code zone
  for _ in $(seq 1 "$n"); do
    line="$(request_once "$url")"
    code="${line%% *}"
    zone="${line##* }"
    if [ "$code" != "200" ]; then bad=$((bad + 1)); continue; fi
    # A 200 from a zone that is neither LOCAL_ZONE nor REMOTE_ZONE counts as bad.
    if [ "$zone" = "$LOCAL_ZONE" ]; then local_n=$((local_n + 1))
    elif [ "$zone" = "$REMOTE_ZONE" ]; then other_n=$((other_n + 1))
    else bad=$((bad + 1)); fi
  done
  printf '%s %s %s\n' "$bad" "$local_n" "$other_n"
}

if [ "$mode" = "killed" ]; then
  # Wait until one request is answered by the remote zone, then sample.
  ok=0
  for _ in $(seq 1 45); do
    line="$(request_once "$url")"
    if [ "${line%% *}" = "200" ] && [ "${line##* }" = "$REMOTE_ZONE" ]; then ok=1; break; fi
    sleep 2
  done
  [ "$ok" -eq 1 ] || { echo "FAIL: no 200 from $REMOTE_ZONE within 90 seconds" >&2; exit 1; }
  read -r bad local_n other_n <<<"$(sample 100)"
  echo "100 requests: non-200=$bad local=$local_n other=$other_n"
  [ "$bad" -eq 0 ] && [ "$local_n" -eq 0 ] && [ "$other_n" -eq 100 ] || { echo "FAIL: expected all 100 answers 200 from $REMOTE_ZONE" >&2; exit 1; }
  echo "stage 07 OK (killed)"
  exit 0
fi

# up and restored: wait up to 90 seconds for the local zone to answer again, then sample.
ok=0
for _ in $(seq 1 45); do
  line="$(request_once "$url")"
  if [ "${line%% *}" = "200" ] && [ "${line##* }" = "$LOCAL_ZONE" ]; then ok=1; break; fi
  sleep 2
done
[ "$ok" -eq 1 ] || { echo "FAIL: the local zone '$LOCAL_ZONE' did not answer within 90 seconds" >&2; exit 1; }
# Only "up" runs right after apply.sh rolled the gateway, when some requests fail for a few seconds
# "restored" follows 20-restore-local.sh, which does not roll the gateway, so no wait.
if [ "$mode" = "up" ]; then wait_gateway_warm "$url" || exit 1; fi
read -r bad local_n other_n <<<"$(sample 100)"
echo "100 requests: non-200=$bad local=$local_n other=$other_n"
[ "$bad" -eq 0 ] && [ "$other_n" -eq 0 ] || { echo "FAIL: expected all 200 from $LOCAL_ZONE" >&2; exit 1; }

if [ "$mode" = "restored" ]; then
  "$here/../02-app/verify-switch.sh" 0 "$ctx1"
  "$here/../02-app/verify-switch.sh" 0 "$ctx2"
fi
echo "stage 07 OK ($mode)"
