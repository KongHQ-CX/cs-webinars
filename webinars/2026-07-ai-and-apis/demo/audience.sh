set -a; source .env; set +a
KC=${KC_ADMIN_URL:-http://localhost:8081}
tok() { curl -s -X POST "$KC/realms/master/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=admin-cli -d username=admin -d password=admin \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])'; }
KCADMIN=$(tok); H=(-H "Authorization: Bearer $KCADMIN" -H "Content-Type: application/json")

# 1) create a client scope that injects aud=inventory-api
curl -s -o /dev/null -w "scope create: %{http_code}\n" "${H[@]}" -X POST "$KC/admin/realms/mcp/client-scopes" -d '{
  "name":"inventory-api","protocol":"openid-connect",
  "attributes":{"include.in.token.scope":"true","display.on.consent.screen":"false"},
  "protocolMappers":[{
    "name":"inventory-api-aud","protocol":"openid-connect",
    "protocolMapper":"oidc-audience-mapper",
    "config":{"included.client.audience":"inventory-api",
              "access.token.claim":"true","id.token.claim":"false"}
  }]}'

# 2) find the scope id and the mcp-kong client id
SID=$(curl -s "$KC/admin/realms/mcp/client-scopes" "${H[@]}" \
  | python3 -c 'import sys,json;print(next(s["id"] for s in json.load(sys.stdin) if s["name"]=="inventory-api"))')
CID=$(curl -s "$KC/admin/realms/mcp/clients?clientId=mcp-kong" "${H[@]}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')

# 3) attach the scope to mcp-kong as a DEFAULT scope (so the user's tokens can carry it)
curl -s -o /dev/null -w "attach scope: %{http_code}\n" "${H[@]}" \
  -X PUT "$KC/admin/realms/mcp/clients/$CID/default-client-scopes/$SID"
