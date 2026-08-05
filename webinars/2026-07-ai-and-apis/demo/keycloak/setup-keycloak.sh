#!/usr/bin/env bash
# Provision the "mcp" realm in the running Keycloak via the Admin REST API.
# Creates:
#   - realm   mcp
#   - client  mcp-kong      (confidential, service account, direct-access grants,
#                            Standard Token Exchange ENABLED) -> the agent's tokens
#                            and Kong introspection; also the token-exchange client
#   - client  mcp-inspector (public, PKCE) -> interactive MCP Inspector login
#   - client  inventory-api (audience target for token exchange)
#   - user    demo / demo
set -euo pipefail
KC=${KC_ADMIN_URL:-http://localhost:8081}
REALM=mcp
CLIENT_SECRET=${KC_CLIENT_SECRET:-mcp-kong-secret}

echo "Getting admin token from $KC ..."
TOKEN=$(curl -sf -X POST "$KC/realms/master/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=admin-cli \
  -d username=admin -d password=admin | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
H=(-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")

echo "Creating realm $REALM ..."
curl -s "${H[@]}" -X POST "$KC/admin/realms" \
  -d "{\"realm\":\"$REALM\",\"enabled\":true}" >/dev/null || true

echo "Creating confidential client mcp-kong (service account + token exchange) ..."
curl -s "${H[@]}" -X POST "$KC/admin/realms/$REALM/clients" -d "{
  \"clientId\":\"mcp-kong\",\"enabled\":true,\"protocol\":\"openid-connect\",
  \"publicClient\":false,\"serviceAccountsEnabled\":true,
  \"standardFlowEnabled\":false,\"directAccessGrantsEnabled\":true,
  \"secret\":\"$CLIENT_SECRET\",
  \"attributes\":{\"standard.token.exchange.enabled\":\"true\"}}" >/dev/null || true

echo "Creating audience target client inventory-api (token-exchange target) ..."
curl -s "${H[@]}" -X POST "$KC/admin/realms/$REALM/clients" -d '{
  "clientId":"inventory-api","enabled":true,"protocol":"openid-connect",
  "publicClient":false,"standardFlowEnabled":false,
  "serviceAccountsEnabled":false,
  "attributes":{"standard.token.exchange.enabled":"true"}}' >/dev/null || true

echo "Creating public client mcp-inspector (PKCE, redirect to the MCP Inspector) ..."
curl -s "${H[@]}" -X POST "$KC/admin/realms/$REALM/clients" -d '{
  "clientId":"mcp-inspector","enabled":true,"protocol":"openid-connect",
  "publicClient":true,"standardFlowEnabled":true,
  "redirectUris":["http://localhost:6274/*"],
  "webOrigins":["http://localhost:6274"],
  "attributes":{"pkce.code.challenge.method":"S256"}}' >/dev/null || true

echo "Creating user demo/demo ..."
curl -s "${H[@]}" -X POST "$KC/admin/realms/$REALM/users" -d '{
  "username":"demo","enabled":true,
  "credentials":[{"type":"password","value":"demo","temporary":false}]}' >/dev/null || true

echo "Done. Issuer: ${KC%/}/realms/$REALM"
echo "  client_credentials / password: client_id=mcp-kong secret=$CLIENT_SECRET"
echo "  token-exchange target audience: inventory-api"
echo "  interactive login:  user=demo pass=demo (client mcp-inspector)"
