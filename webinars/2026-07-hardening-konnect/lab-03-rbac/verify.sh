#!/usr/bin/env bash
# Lab 3 verification — confirms RBAC least privilege.
# Uses ADMIN_PAT for admin actions and the system account's generated
# access token (written by 02-assign-roles.sh) for the developer-scoped calls.
#
# Teams/Users/RBAC are org-level resources in Konnect's Identity Management
# API (global.api.konghq.com/v3), NOT region-scoped like Control Planes
# (<region>.api.konghq.com/v2) — hence the two separate base URLs below.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/verify-common.sh"

: "${KONNECT_PAT:=<type your Konnect PAT>}"
: "${KONNECT_CONTROL_PLANE_ID:=<type your Konnect Control plane ID>}"

if [[ -z "${DEV_PAT:-}" ]]; then
  DEV_PAT="$(cat "$SCRIPT_DIR/../.system-account-token" 2>/dev/null || true)"
fi
if [[ -z "$DEV_PAT" ]]; then
  echo "FAIL: No system account token found. Run 02-assign-roles.sh first, or set DEV_PAT explicitly." >&2
  exit 1
fi

KONNECT_REGION="${KONNECT_REGION:-in}"
TEAMS_BASE_URL="https://global.api.konghq.com/v3"
CP_URL="https://${KONNECT_REGION}.api.konghq.com/v2/control-planes/${KONNECT_CONTROL_PLANE_ID}/core-entities"
ADMIN_AUTH="Authorization: Bearer ${KONNECT_PAT}"
DEV_AUTH="Authorization: Bearer ${DEV_PAT}"

# curl -f hides the response body on HTTP errors, turning failures into
# opaque silent exits under `set -e`. This helper prints status + body on
# failure so problems are diagnosable instead of swallowed.
konnect_api() {
  local url="$1" auth="$2"
  local resp status body
  resp=$(curl -s -w '\n%{http_code}' "$url" -H "$auth")
  status=$(echo "$resp" | tail -1)
  body=$(echo "$resp" | sed '$d')
  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    echo "FAIL: GET $url -> HTTP $status" >&2
    echo "$body" >&2
    return 1
  fi
  echo "$body"
}

TEAM_ID=$(cat .team-id 2>/dev/null || echo "unknown")
echo "==> Team ID: $TEAM_ID"

echo ""
echo "--- Team exists in Konnect ---"
TEAM=$(konnect_api "${TEAMS_BASE_URL}/teams/${TEAM_ID}" "$ADMIN_AUTH")
echo "$TEAM" | python3 -m json.tool
check_pass "Team found in Konnect"

echo ""
echo "--- Team role is viewer scoped to control plane only ---"
ROLES=$(konnect_api "${TEAMS_BASE_URL}/teams/${TEAM_ID}/assigned-roles" "$ADMIN_AUTH")
echo "$ROLES" | python3 -m json.tool
# role_name is a display string (e.g. "Viewer", not "viewer") — match
# case-insensitively so exact catalog casing doesn't silently break this.
if echo "$ROLES" | python3 -c "
import sys,json
roles = json.load(sys.stdin).get('data',[])
sys.exit(0 if any(r.get('role_name','').lower()=='viewer' and r.get('entity_id')=='${KONNECT_CONTROL_PLANE_ID}' for r in roles) else 1)
"; then
  check_pass "Viewer role scoped to CP ${KONNECT_CONTROL_PLANE_ID}"
else
  check_fail "Viewer role scoped to CP ${KONNECT_CONTROL_PLANE_ID}" "expected scoped viewer role not found"
fi

echo ""
echo "--- System account CAN list services (read) ---"
# No -f here: we want the status code even on non-2xx, not curl exiting
# non-zero and killing the script under `set -e` before we can inspect it.
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "${CP_URL}/services" -H "$DEV_AUTH")
if [[ "$HTTP_CODE" == "200" ]]; then
  check_pass "System account can GET services (HTTP 200)"
else
  check_warn "System account can GET services" "unexpected HTTP $HTTP_CODE"
fi

echo ""
echo "--- System account CANNOT delete services (write blocked) ---"
# Try to delete a non-existent service — should be 403, not 404.
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
  "${CP_URL}/services/00000000-0000-0000-0000-000000000000" \
  -H "$DEV_AUTH")
if [[ "$HTTP_CODE" == "403" ]]; then
  check_pass "System account DELETE blocked with 403"
else
  check_fail "System account DELETE blocked with 403" "got HTTP $HTTP_CODE"
fi

verify_summary "Lab 3 (RBAC)"
