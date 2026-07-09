#!/usr/bin/env bash
# Assigns the Viewer role to the team, scoped to one control plane.
# Also creates a system account, generates an access token for it, and
# adds it to the team (instead of inviting a human developer user).
#
# Teams/Users/RBAC are org-level resources in Konnect's Identity Management
# API, NOT region-scoped like Control Planes/Vaults — they live under
# global.api.konghq.com/v3, not <region>.api.konghq.com/v2. The entity being
# scoped (KONNECT_CONTROL_PLANE_ID) is still region-specific, so
# KONNECT_REGION is kept for the assigned-roles entity_region field only.
set -euo pipefail

: "${KONNECT_PAT:=<type your Konnect PAT>}"
: "${KONNECT_CONTROL_PLANE_ID:=<type your Konnect Control plane ID>}"
SYSTEM_ACCOUNT_NAME="${SYSTEM_ACCOUNT_NAME:-kong-developer-svc}"
# Set ROLE_NAME explicitly to skip the catalog lookup below (e.g. if you
# already know the exact role name Konnect expects).
ROLE_NAME="${ROLE_NAME:-Viewer}"

KONNECT_REGION="${KONNECT_REGION:-in}"
BASE_URL="https://global.api.konghq.com/v3"
AUTH="Authorization: Bearer ${KONNECT_PAT}"

# curl -f hides the response body on HTTP errors, turning failures into
# opaque silent exits under `set -e`. This helper prints status + body on
# failure so problems are diagnosable instead of swallowed.
konnect_api() {
  local method="$1" url="$2" data="${3:-}"
  local resp status body
  if [[ -n "$data" ]]; then
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "$AUTH" -H "Content-Type: application/json" -d "$data")
  else
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "$AUTH")
  fi
  status=$(echo "$resp" | tail -1)
  body=$(echo "$resp" | sed '$d')
  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    echo "FAIL: $method $url -> HTTP $status" >&2
    echo "$body" >&2
    return 1
  fi
  echo "$body"
}

TEAM_ID=$(cat .team-id 2>/dev/null || { echo "Run 01-create-team.sh first"; exit 1; })
echo "==> Using team ID: $TEAM_ID"

if [[ -z "$ROLE_NAME" ]]; then
  echo ""
  echo "==> Looking up the exact role name for read-only access to Control Planes"
  # "viewer" 404s as "role not found" — role_name must match Konnect's actual
  # role catalog exactly (e.g. it may be "Viewer" capitalized, or a more
  # specific name like "Control Plane Viewer"). Query the catalog instead of
  # guessing a third time.
  ROLES_CATALOG=$(konnect_api GET "${BASE_URL}/roles?entity_type_name=Control%20Planes")
  echo "$ROLES_CATALOG" | python3 -m json.tool
  ROLE_NAME=$(echo "$ROLES_CATALOG" | python3 -c "
import sys, json
d = json.load(sys.stdin)
roles = d.get('data', [])
# Prefer an exact case-insensitive match on 'viewer', else fall back to the first read-only-sounding role.
for r in roles:
    if r.get('name', '').lower() == 'viewer':
        print(r['name']); sys.exit(0)
for r in roles:
    if 'view' in r.get('name', '').lower() or 'read' in r.get('name', '').lower():
        print(r['name']); sys.exit(0)
sys.exit(1)
" || echo "")

  if [[ -z "$ROLE_NAME" ]]; then
    echo "FAIL: Could not find a read-only role for 'Control Planes' in the roles catalog above." >&2
    echo "      Pick the correct role_name from the list and re-run with ROLE_NAME=<name> bash 02-assign-roles.sh" >&2
    exit 1
  fi
fi
echo "==> Using role: $ROLE_NAME"

echo ""
echo "==> Assigning '$ROLE_NAME' role — scoped to control plane ${KONNECT_CONTROL_PLANE_ID}"
# entity_type_name is a display-style constant ("Control Planes", not
# "control-planes") — confirmed from the API's own 400 error listing valid
# values: API Products, APIs, Add Ons, Application Auth Strategies, Audit
# Logs, Auth Servers, Control Planes, DCR Providers, Dashboards,
# Directories, Identity, MCP Servers, Mesh Control Planes, Metering,
# Networks, Portals, Reports, Runtime Groups, Service Hub.
ROLE_RESPONSE=$(konnect_api POST "${BASE_URL}/teams/${TEAM_ID}/assigned-roles" "{
    \"role_name\": \"${ROLE_NAME}\",
    \"entity_id\": \"${KONNECT_CONTROL_PLANE_ID}\",
    \"entity_type_name\": \"Control Planes\",
    \"entity_region\": \"${KONNECT_REGION}\"
  }")
echo "$ROLE_RESPONSE" | python3 -m json.tool

echo ""
echo "==> Creating system account: $SYSTEM_ACCOUNT_NAME"
SA_RESPONSE=$(konnect_api POST "${BASE_URL}/system-accounts" "{
    \"name\": \"${SYSTEM_ACCOUNT_NAME}\",
    \"description\": \"Service account for read-only access to kong-air control plane. Created by Lab 3.\"
  }")
echo "$SA_RESPONSE" | python3 -m json.tool

SA_ID=$(echo "$SA_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "$SA_ID" > .system-account-id
echo "==> System account created. ID: $SA_ID (saved to .system-account-id)"

echo ""
echo "==> Generating access token for system account $SA_ID"
TOKEN_RESPONSE=$(konnect_api POST "${BASE_URL}/system-accounts/${SA_ID}/access-tokens" "{
    \"name\": \"lab-03-verify-token\",
    \"expires_at\": \""2026-10-24T23:59:59Z"\"
  }")
echo "$TOKEN_RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
redacted = {k: ('<redacted>' if k in ('token', 'access_token') else v) for k, v in d.items()}
print(json.dumps(redacted, indent=2))
"

SA_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token') or d.get('access_token',''))")
if [[ -n "$SA_TOKEN" ]]; then
  echo "$SA_TOKEN" > .system-account-token
  chmod 600 .system-account-token
  echo "==> Token generated and saved to .system-account-token (not printed; local file only)"
else
  echo "FAIL: Could not extract token from response above." >&2
  exit 1
fi

echo ""
echo "==> Adding system account $SA_ID to team $TEAM_ID"
konnect_api POST "${BASE_URL}/teams/${TEAM_ID}/system-accounts" "{\"id\": \"${SA_ID}\"}" | python3 -m json.tool

echo ""
echo "==> Current team roles:"
konnect_api GET "${BASE_URL}/teams/${TEAM_ID}/assigned-roles" | python3 -m json.tool
