#!/usr/bin/env bash
# Creates a scoped Konnect team for developers and writes its ID to .team-id.
#
# Teams/Users/RBAC are org-level resources in Konnect's Identity Management
# API, NOT region-scoped like Control Planes/Vaults — they live under
# global.api.konghq.com/v3, not <region>.api.konghq.com/v2.
set -euo pipefail

: "${KONNECT_PAT:=<type your Konnect PAT>}"
: "${KONNECT_CONTROL_PLANE_ID:=<type your Konnect Control plane ID>}"

BASE_URL="https://global.api.konghq.com/v3"
AUTH="Authorization: Bearer ${KONNECT_PAT}"
TEAM_NAME="${TEAM_NAME:-kong-developer}"

# curl -f hides the response body on HTTP errors, which combined with `set -e`
# kills the script with no visible reason. Capture status + body explicitly.
RESP=$(curl -s -w '\n%{http_code}' -X POST "${BASE_URL}/teams" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"${TEAM_NAME}\",
    \"description\": \"Read-only access to kong-air control plane. Created by Lab 3.\"
  }")
STATUS=$(echo "$RESP" | tail -1)
RESPONSE=$(echo "$RESP" | sed '$d')

echo "==> Creating team: $TEAM_NAME"
if [[ "$STATUS" -lt 200 || "$STATUS" -ge 300 ]]; then
  echo "FAIL: POST ${BASE_URL}/teams -> HTTP $STATUS" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

echo "$RESPONSE" | python3 -m json.tool

TEAM_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "$TEAM_ID" > .team-id
echo ""
echo "==> Team created. ID: $TEAM_ID (saved to .team-id)"

echo ""
echo "==> All teams:"
curl -sf "${BASE_URL}/teams" -H "$AUTH" | python3 -m json.tool
