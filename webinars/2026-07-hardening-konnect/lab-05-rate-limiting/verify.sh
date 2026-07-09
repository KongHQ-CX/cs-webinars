#!/usr/bin/env bash
# Lab 5 verification — rate limiting, audit logs, and DP health.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/verify-common.sh"

: "${KONNECT_PAT:?Set KONNECT_PAT}"
: "${KONNECT_CONTROL_PLANE_ID:?Set KONNECT_CONTROL_PLANE_ID}"

KONNECT_REGION="${KONNECT_REGION:-us}"
BASE_URL="https://${KONNECT_REGION}.api.konghq.com/v2"
CP_URL="${BASE_URL}/control-planes/${KONNECT_CONTROL_PLANE_ID}/core-entities"
AUTH="Authorization: Bearer ${KONNECT_PAT}"

echo "--- Control #24: Rate-limiting plugin exists ---"
# The ?name= query filter is unreliable against this API (observed returning
# the wrong entity regardless of the name given when multiple entities
# exist — see 00-base/07-kong-services-routes.sh). Fetch the full list and
# filter by exact name match in Python instead.
ALL_PLUGINS=$(curl -sf "${CP_URL}/plugins" -H "$AUTH")
PLUGINS=$(echo "$ALL_PLUGINS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [p for p in d.get('data', []) if p.get('name') == 'rate-limiting']
print(json.dumps({'data': matches}))
")
echo "$PLUGINS" | python3 -m json.tool
RL_COUNT=$(echo "$PLUGINS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))")
if [[ "$RL_COUNT" -ge 1 ]]; then
  check_pass "rate-limiting plugin found"
else
  check_fail "rate-limiting plugin found" "none configured"
fi

echo ""
echo "--- Control #24: Rate-limiting policy is redis ---"
POLICY=$(echo "$PLUGINS" | python3 -c "
import sys,json
d = json.load(sys.stdin)
p = d['data'][0]['config']['policy']
print(f'policy: {p}')
")
echo "$POLICY"
if echo "$POLICY" | grep -q "policy: redis"; then
  check_pass "Rate-limiting policy is redis"
else
  check_fail "Rate-limiting policy is redis" "$POLICY"
fi

echo ""
echo "--- Control #19: Recent audit log events ---"
LOGS=$(curl -sf "${BASE_URL}/audit-logs?page_size=5" -H "$AUTH")
echo "$LOGS" | python3 -m json.tool
LOG_COUNT=$(echo "$LOGS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null || echo "0")
if [[ "$LOG_COUNT" -ge 1 ]]; then
  check_pass "$LOG_COUNT audit log entries found"
else
  check_warn "Audit log entries found" "none — check webhook config and make a config change"
fi

echo ""
echo "--- Control #4/#5: DP node health ---"
NODES=$(curl -sf "${BASE_URL}/control-planes/${KONNECT_CONTROL_PLANE_ID}/nodes" -H "$AUTH")
echo "$NODES" | python3 -m json.tool
NODE_HEALTH=$(python3 - <<PYEOF
import json
data = json.loads("""${NODES}""")
nodes = data.get('items', data.get('data', []))
if not nodes:
    print('WARN\tNo nodes returned')
else:
    disconnected = [n for n in nodes if n.get('status') != 'connected']
    if disconnected:
        detail = ', '.join(f"{n.get('hostname','?')} -> {n.get('status','?')}" for n in disconnected)
        print(f'FAIL\t{len(disconnected)} node(s) not connected: {detail}')
    else:
        print(f'PASS\tAll {len(nodes)} node(s) connected')
PYEOF
)
IFS=$'\t' read -r NODE_STATUS NODE_DETAIL <<< "$NODE_HEALTH"
case "$NODE_STATUS" in
  PASS) check_pass "$NODE_DETAIL" ;;
  FAIL) check_fail "All DP nodes connected" "$NODE_DETAIL" ;;
  *) check_warn "DP node health" "$NODE_DETAIL" ;;
esac

verify_summary "Lab 5 (Rate Limiting)"
