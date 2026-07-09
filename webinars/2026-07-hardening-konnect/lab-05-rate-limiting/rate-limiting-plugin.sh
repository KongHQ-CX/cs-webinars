#!/usr/bin/env bash
# Creates a global rate-limiting plugin with Redis backend (200 req/min).
set -euo pipefail

: "${KONNECT_PAT:?Set KONNECT_PAT}"
: "${KONNECT_CONTROL_PLANE_ID:?Set KONNECT_CONTROL_PLANE_ID}"

KONNECT_REGION="${KONNECT_REGION:-us}"
BASE_URL="https://${KONNECT_REGION}.api.konghq.com/v2/control-planes/${KONNECT_CONTROL_PLANE_ID}/core-entities"
AUTH="Authorization: Bearer ${KONNECT_PAT}"

REDIS_HOST="${REDIS_HOST:-redis.kong.svc}"
REDIS_PORT="${REDIS_PORT:-6379}"
LIMIT="${RATE_LIMIT:-200}"

echo "==> Creating global rate-limiting plugin"
echo "    Redis: ${REDIS_HOST}:${REDIS_PORT}"
echo "    Limit: ${LIMIT} req/min"

RESP=$(curl -sf -X POST "${BASE_URL}/plugins" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"rate-limiting\",
    \"enabled\": true,
    \"config\": {
      \"minute\": ${LIMIT},
      \"policy\": \"redis\",
      \"redis\": {
        \"host\": \"${REDIS_HOST}\",
        \"port\": ${REDIS_PORT},
        \"timeout\": 2000,
        \"database\": 0
      },
      \"fault_tolerant\": true,
      \"hide_client_headers\": false,
      \"error_code\": 429,
      \"error_message\": \"API rate limit exceeded\"
    }
  }")

echo "$RESP" | python3 -m json.tool
PLUGIN_ID=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "$PLUGIN_ID" > .rate-limit-plugin-id
echo ""
echo "==> Plugin created: $PLUGIN_ID (saved to .rate-limit-plugin-id)"
echo "    Waiting 30s for config to propagate to DP..."
sleep 30
echo "    Ready."
