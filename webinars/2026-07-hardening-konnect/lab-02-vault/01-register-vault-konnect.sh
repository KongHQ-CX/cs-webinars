#!/usr/bin/env bash
# Registers the HCV vault backend with the Konnect Admin API
# and creates a key-auth plugin that uses vault references.
set -euo pipefail

: "${KONNECT_PAT:=<type your Konnect PAT>}"
: "${KONNECT_CONTROL_PLANE_ID:=<type your Konnect Control plane ID>}"
: "${VAULT_ADDR:=https://vault.vault.svc:8200}"

KONNECT_REGION="${KONNECT_REGION:-in}"
BASE_URL="https://${KONNECT_REGION}.api.konghq.com/v2/control-planes/${KONNECT_CONTROL_PLANE_ID}/core-entities"
AUTH="Authorization: Bearer ${KONNECT_PAT}"

# Konnect's vault entity needs its own approle_role_id/approle_secret_id to
# authenticate to Vault — separate from KONG_VAULT_HCV_APPROLE_ROLE_ID, which
# only authenticates the DP's local Kong process. Both come from the same
# AppRole, seeded into Secret 'kong-vault-approle' by 00-base/04-vault-init.sh.
ROLE_ID=$(kubectl get secret kong-vault-approle -n kong -o jsonpath='{.data.role_id}' 2>/dev/null | base64 -d || echo "")
SECRET_ID=$(kubectl get secret kong-vault-approle -n kong -o jsonpath='{.data.secret_id}' 2>/dev/null | base64 -d || echo "")
if [[ -z "$ROLE_ID" || -z "$SECRET_ID" ]]; then
  echo "FAIL: Secret 'kong-vault-approle' not found or incomplete — run 00-base/04-vault-init.sh first" >&2
  exit 1
fi

# curl -f hides the response body on HTTP errors, which turns every failure
# into an opaque "Expecting value" from the downstream `python3 -m json.tool`.
# This helper prints the status code and body, and only feeds valid 2xx
# bodies onward, so failures are diagnosable instead of silently swallowed.
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

# prefix must not collide with Kong's reserved vault prefixes
# (env, aws, azure, gcp, hcv, konnect, conjur, fs, azure-certs).
#
# ssl_verify must be explicitly true here (NOT tls_verify — that field name
# doesn't exist on this entity and 400s with "unknown field"): the DP
# enforces TLS certificate verification globally (Konnect-managed CPs default
# tls_certificate_verify to on), and Kong rejects any vault config that tries
# to disable ssl_verify per-entity while that global flag is on ("ssl_verify:
# global tls_certificate_verify option is enabled, ssl_verify cannot be
# disabled" — note the error names the field ssl_verify, which is what
# pointed at the correct name here). The DP trusts the Vault server cert via
# vault_hcv_tls_ca_cert in values.yaml (the lab CA bundle mounted from
# Secret 'kong-labs-ca').
VAULT_CONFIG="{
    \"name\": \"hcv\",
    \"prefix\": \"kongair-vault\",
    \"description\": \"HashiCorp Vault — Kong-Air lab secrets\",
    \"config\": {
      \"protocol\": \"https\",
      \"host\": \"vault.vault.svc\",
      \"port\": 8200,
      \"mount\": \"kv\",
      \"kv\": \"v2\",
      \"auth_method\": \"approle\",
      \"approle_role_id\": \"${ROLE_ID}\",
      \"approle_secret_id\": \"${SECRET_ID}\",
      \"ssl_verify\": true
    }
  }"

# Fetch the full list and filter client-side — see the routes lookup below
# for why the ?param= query filter isn't trusted on this API.
EXISTING_VAULT_ID=$(konnect_api GET "${BASE_URL}/vaults" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [v for v in d.get('data', []) if v.get('prefix') == 'kongair-vault']
print(matches[0]['id'] if matches else '')
" 2>/dev/null || echo "")

if [[ -n "$EXISTING_VAULT_ID" ]]; then
  echo "==> Vault 'kongair-vault' already registered ($EXISTING_VAULT_ID) — current config:"
  konnect_api GET "${BASE_URL}/vaults/${EXISTING_VAULT_ID}" | python3 -m json.tool
  echo "==> Updating config"
  # Kong's Admin API vault entity does not support PATCH (partial update) —
  # only PUT (full replace), same as most core entities.
  konnect_api PUT "${BASE_URL}/vaults/${EXISTING_VAULT_ID}" "$VAULT_CONFIG" | python3 -m json.tool
else
  echo "==> Registering HCV vault backend in Konnect"
  konnect_api POST "${BASE_URL}/vaults" "$VAULT_CONFIG" | python3 -m json.tool
fi

echo ""
echo "==> Creating key-auth plugin on /flights route using vault reference"
# The ?name= query filter is unreliable against this API (observed returning
# the wrong entity regardless of the name given when multiple entities
# exist — see 00-base/07-kong-services-routes.sh). Fetch the full list
# (page_size=200 so pagination doesn't silently hide entities past page 1 —
# default page size appears to be 10) and filter by exact name in Python.
ROUTE_ID=$(konnect_api GET "${BASE_URL}/routes?page_size=200" \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [r for r in d.get('data', []) if r.get('name') == 'flights-route']
print(matches[0]['id'] if matches else '')
" 2>/dev/null || echo "")

if [[ -z "$ROUTE_ID" ]]; then
  echo "WARN: Could not find flights-route. Create it in Konnect first, then re-run."
else
  EXISTING_PLUGIN_ID=$(konnect_api GET "${BASE_URL}/routes/${ROUTE_ID}/plugins" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [p for p in d.get('data', []) if p.get('name') == 'key-auth']
print(matches[0]['id'] if matches else '')
" 2>/dev/null || echo "")

  if [[ -n "$EXISTING_PLUGIN_ID" ]]; then
    echo "==> key-auth plugin already exists on flights-route ($EXISTING_PLUGIN_ID) — skipping"
  else
    konnect_api POST "${BASE_URL}/routes/${ROUTE_ID}/plugins" '{
        "name": "key-auth",
        "config": {
          "key_names": ["X-API-Key"]
        }
      }' | python3 -m json.tool
  fi

  echo ""
  echo "==> Creating consumer with key credential via vault reference"
  EXISTING_CONSUMER_ID=$(konnect_api GET "${BASE_URL}/consumers?username=kong-air-client" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')" 2>/dev/null || echo "")

  if [[ -n "$EXISTING_CONSUMER_ID" ]]; then
    echo "==> Consumer 'kong-air-client' already exists ($EXISTING_CONSUMER_ID)"
    CONSUMER_ID="$EXISTING_CONSUMER_ID"
  else
    CONSUMER_RESP=$(konnect_api POST "${BASE_URL}/consumers" '{"username": "kong-air-client"}')
    CONSUMER_ID=$(echo "$CONSUMER_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  fi
  echo "Consumer ID: $CONSUMER_ID"

  EXISTING_KEY_AUTH_ID=$(konnect_api GET "${BASE_URL}/consumers/${CONSUMER_ID}/key-auth" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')" 2>/dev/null || echo "")

  if [[ -n "$EXISTING_KEY_AUTH_ID" ]]; then
    echo "==> Consumer already has a key-auth credential ($EXISTING_KEY_AUTH_ID) — skipping"
  else
    konnect_api POST "${BASE_URL}/consumers/${CONSUMER_ID}/key-auth" '{
        "key": "{vault://kongair-vault/kong-air/key-auth#api_key}"
      }' | python3 -m json.tool
  fi
fi

echo ""
echo "==> Verifying vault appears in Konnect"
konnect_api GET "${BASE_URL}/vaults" | python3 -m json.tool
