#!/usr/bin/env bash
# Stage 04 check, run after 10-failure-on.sh on ready-1:
#   the switch reads 50 on every demo pod in both zones, and 100 requests through the gateway
#   give 503 on 25 to 75 of them (mean 50, so the band is about 5 standard deviations wide).
# Env: CTX_1 (default ready-1), CTX_2 (default ready-2), GATEWAY_URL (default: the gateway Service address).
#
# Prerequisites: stage 03 is in place and 10-failure-on.sh ran. Run on ready-1.
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"
# shellcheck source=../../lib/gateway.sh
. "$WEBINAR_CODE_DIR/lib/gateway.sh"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
switch_check="$here/../02-app/verify-switch.sh"
ctx1="${CTX_1:-ready-1}"
ctx2="${CTX_2:-ready-2}"
require_ctx_1 || exit 1

"$switch_check" 50 "$ctx1"
"$switch_check" 50 "$ctx2"

url="$(gateway_url)" || exit 1
read -r ok fail other <<<"$(count_requests "$url" 100)"
echo "100 requests: 200=$ok 503=$fail other=$other"
if [ "$other" -ne 0 ] || [ "$fail" -lt 25 ] || [ "$fail" -gt 75 ]; then
  echo "FAIL: expected only 200 and 503, with 503 on 25 to 75 of 100" >&2
  exit 1
fi
echo "stage 04 OK"
