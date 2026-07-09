#!/usr/bin/env bash
# Top-level cleanup — removes every resource created across 00-base and the
# labs: Kong Services/Routes, the vault backend + key-auth plugin/consumer,
# the rate-limiting plugin, the RBAC team/user, and the kong-dp Helm release.
#
# Teams/Users/RBAC are org-level resources in Konnect's Identity Management
# API (global.api.konghq.com/v3), NOT region-scoped like Control
# Planes/Services/Routes/Plugins (<region>.api.konghq.com/v2) — see
# lab-03-rbac/01-create-team.sh.
set -euo pipefail

: "${KONNECT_PAT:=<type your Konnect PAT>}"
: "${KONNECT_CONTROL_PLANE_ID:=<type your Konnect Control plane ID>}"

KONNECT_REGION="${KONNECT_REGION:-in}"
BASE_URL="https://${KONNECT_REGION}.api.konghq.com/v2/control-planes/${KONNECT_CONTROL_PLANE_ID}/core-entities"
GLOBAL_URL="https://global.api.konghq.com/v3"
AUTH="Authorization: Bearer ${KONNECT_PAT}"

NAMESPACE="${NAMESPACE:-kong}"
RELEASE="${RELEASE:-kong-dp}"
TEAM_NAME="${TEAM_NAME:-kong-developer}"

# curl -f hides the response body on HTTP errors, turning failures into
# opaque silent exits under `set -e`. Print status + body on failure instead.
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

# Same pagination caveat as 00-base/07-kong-services-routes.sh: a plain
# unpaginated GET only returns page 1 and can silently miss entities.
konnect_list_all() {
  local url="$1"
  local sep="?"
  [[ "$url" == *"?"* ]] && sep="&"
  konnect_api GET "${url}${sep}page_size=200"
}

delete_by_name() {
  local entity="$1" name="$2"
  local ids
  ids=$(konnect_list_all "${BASE_URL}/${entity}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [e['id'] for e in d.get('data', []) if e.get('name') == '${name}']
print('\n'.join(matches))
" 2>/dev/null || echo "")
  if [[ -z "$ids" ]]; then
    echo "SKIP: no ${entity%s} named '${name}'"
    return 0
  fi
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "==> Deleting ${entity%s} '${name}' ($id)"
    konnect_api DELETE "${BASE_URL}/${entity}/${id}" >/dev/null
  done <<< "$ids"
}

echo "==> Step 1: Deleting Kong Routes + Services (00-base)"
# Routes must go before their parent Services.
delete_by_name "routes" "flights-route"
delete_by_name "routes" "bookings-route"
delete_by_name "services" "flights-service"
delete_by_name "services" "bookings-service"

echo ""
echo "==> Step 2: Removing vault backend + key-auth plugin/consumer (lab-02)"
# Consumer credentials and route plugins must go before the vault entity
# itself — the key-auth credential references it via vault://kongair-vault/...
ROUTE_ID=$(konnect_list_all "${BASE_URL}/routes" | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [r['id'] for r in d.get('data', []) if r.get('name') == 'flights-route']
print(matches[0] if matches else '')
" 2>/dev/null || echo "")
if [[ -n "$ROUTE_ID" ]]; then
  KEY_AUTH_PLUGIN_ID=$(konnect_api GET "${BASE_URL}/routes/${ROUTE_ID}/plugins" | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [p['id'] for p in d.get('data', []) if p.get('name') == 'key-auth']
print(matches[0] if matches else '')
" 2>/dev/null || echo "")
  if [[ -n "$KEY_AUTH_PLUGIN_ID" ]]; then
    echo "==> Deleting key-auth plugin on flights-route ($KEY_AUTH_PLUGIN_ID)"
    konnect_api DELETE "${BASE_URL}/plugins/${KEY_AUTH_PLUGIN_ID}" >/dev/null || true
  else
    echo "SKIP: no key-auth plugin on flights-route"
  fi
else
  echo "SKIP: flights-route not found, skipping its key-auth plugin"
fi

CONSUMER_ID=$(konnect_api GET "${BASE_URL}/consumers?username=kong-air-client" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')" 2>/dev/null || echo "")
if [[ -n "$CONSUMER_ID" ]]; then
  echo "==> Deleting consumer 'kong-air-client' ($CONSUMER_ID)"
  konnect_api DELETE "${BASE_URL}/consumers/${CONSUMER_ID}" >/dev/null || true
else
  echo "SKIP: no consumer named 'kong-air-client'"
fi

VAULT_ID=$(konnect_api GET "${BASE_URL}/vaults" | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [v['id'] for v in d.get('data', []) if v.get('prefix') == 'kongair-vault']
print(matches[0] if matches else '')
" 2>/dev/null || echo "")
if [[ -n "$VAULT_ID" ]]; then
  echo "==> Deleting vault backend 'kongair-vault' ($VAULT_ID)"
  konnect_api DELETE "${BASE_URL}/vaults/${VAULT_ID}" >/dev/null || true
  echo "PASS: vault 'kongair-vault' deleted"
else
  echo "SKIP: no vault registered with prefix 'kongair-vault'"
fi

echo ""
echo "==> Step 3: Deleting rate-limiting plugin (lab-05)"
RL_PLUGIN_ID=$(cat "$(dirname "$0")/lab-05-rate-limiting/.rate-limit-plugin-id" 2>/dev/null || echo "")
if [[ -n "$RL_PLUGIN_ID" ]]; then
  echo "==> Deleting plugin $RL_PLUGIN_ID (from .rate-limit-plugin-id)"
  konnect_api DELETE "${BASE_URL}/plugins/${RL_PLUGIN_ID}" >/dev/null || true
  rm -f "$(dirname "$0")/lab-05-rate-limiting/.rate-limit-plugin-id"
else
  PLUGIN_IDS=$(konnect_list_all "${BASE_URL}/plugins" | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [p['id'] for p in d.get('data', []) if p.get('name') == 'rate-limiting']
print('\n'.join(matches))
" 2>/dev/null || echo "")
  if [[ -z "$PLUGIN_IDS" ]]; then
    echo "SKIP: no rate-limiting plugin found"
  else
    while IFS= read -r id; do
      [[ -z "$id" ]] && continue
      echo "==> Deleting rate-limiting plugin ($id)"
      konnect_api DELETE "${BASE_URL}/plugins/${id}" >/dev/null
    done <<< "$PLUGIN_IDS"
  fi
fi

echo ""
echo "==> Step 4: Removing RBAC team + invited user (lab-03)"
TEAM_ID=$(cat "$(dirname "$0")/lab-03-rbac/.team-id" 2>/dev/null || echo "")
if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID=$(konnect_api GET "${GLOBAL_URL}/teams" | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [t['id'] for t in d.get('data', []) if t.get('name') == '${TEAM_NAME}']
print(matches[0] if matches else '')
" 2>/dev/null || echo "")
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "SKIP: no team named '${TEAM_NAME}' found"
else
  echo "==> Using team ID: $TEAM_ID"

  echo "==> Removing users from team $TEAM_ID"
  USER_IDS=$(konnect_api GET "${GLOBAL_URL}/teams/${TEAM_ID}/users" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print('\n'.join(u['id'] for u in d.get('data', [])))
" 2>/dev/null || echo "")
  while IFS= read -r uid; do
    [[ -z "$uid" ]] && continue
    echo "    Removing user $uid from team"
    konnect_api DELETE "${GLOBAL_URL}/teams/${TEAM_ID}/users/${uid}" >/dev/null || true
  done <<< "$USER_IDS"

  echo "==> Deleting team $TEAM_ID"
  konnect_api DELETE "${GLOBAL_URL}/teams/${TEAM_ID}" >/dev/null
  rm -f "$(dirname "$0")/lab-03-rbac/.team-id"
  echo "PASS: team '${TEAM_NAME}' deleted"
fi

echo ""
echo "==> Step 5: Uninstalling Helm release '$RELEASE' (namespace '$NAMESPACE')"
if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
  helm uninstall "$RELEASE" -n "$NAMESPACE"
  echo "PASS: Helm release '$RELEASE' removed"
else
  echo "SKIP: Helm release '$RELEASE' not found in namespace '$NAMESPACE'"
fi

echo ""
echo "==> Cleanup complete"
