#!/usr/bin/env bash
# Lab 4 verification — no fingerprint headers in responses.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/verify-common.sh"

HOST="${GATEWAY_HOST:-api.kong-air.example.com}"
NAMESPACE="${NAMESPACE:-kong}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"

# flights-route has key-auth enabled (lab-02) with the credential stored in
# Vault at kv/kong-air/key-auth#api_key — fetch it the same way
# 00-base/04-vault-init.sh wrote it, via the root token exec'd into vault-0.
ROOT_TOKEN=$(kubectl get secret vault-root-token -n "$VAULT_NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")
if [[ -z "$ROOT_TOKEN" ]]; then
  echo "FAIL: Secret 'vault-root-token' not found — run 00-base/03-install-vault.sh first" >&2
  exit 1
fi
API_KEY=$(kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- \
  env VAULT_TOKEN="$ROOT_TOKEN" VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true \
  vault kv get -field=api_key kv/kong-air/key-auth)
echo "==> Fetched API key from Vault"

LB_IP=$(kubectl get svc -n "$NAMESPACE" -l app=kong-dp \
  -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}')
echo "==> Gateway IP: $LB_IP"

echo "==> Fetching response headers from /flights"
# curl -I sends a HEAD request, but flights-route only allows GET — Kong's
# router correctly 404s a HEAD request with no matching route, which looked
# like a routing bug but wasn't. Use GET and discard the body instead.
HEADERS=$(curl -sk -o /dev/null -D - -H "Host: $HOST" -H "X-API-Key: $API_KEY" "https://${LB_IP}/flights")
echo "$HEADERS"

echo ""
echo "--- Control #12: No Server / Kong / Via fingerprint headers ---"
MATCHES=$(echo "$HEADERS" | grep -iE '^(server|via|x-kong-)' || true)
if [[ -z "$MATCHES" ]]; then
  check_pass "No fingerprint headers found"
else
  check_fail "No fingerprint headers found" "$MATCHES"
fi

echo ""
echo "--- Control #13: Kong-Debug header absent ---"
DEBUG_HEADER=$(echo "$HEADERS" | grep -i 'kong-debug' || true)
if [[ -z "$DEBUG_HEADER" ]]; then
  check_pass "Kong-Debug header absent"
else
  check_fail "Kong-Debug header absent" "present: $DEBUG_HEADER"
fi

echo ""
echo "--- Control #13: Sending request with Kong-Debug: 1 — should be stripped ---"
# GET, not -I/HEAD — same reasoning as the /flights fetch above.
RESP_HEADERS=$(curl -sk -o /dev/null -D - \
  -H "Host: $HOST" \
  -H "X-API-Key: $API_KEY" \
  -H "Kong-Debug: 1" \
  "https://${LB_IP}/flights")
KONG_DEBUG_ECHO=$(echo "$RESP_HEADERS" | grep -i 'kong' || true)
if [[ -z "$KONG_DEBUG_ECHO" ]]; then
  check_pass "Kong-Debug: 1 request header is stripped from response"
else
  check_fail "Kong-Debug: 1 request header is stripped from response" "$KONG_DEBUG_ECHO"
fi

echo ""
echo "--- Control #16: nginx access log disabled (check pod logs) ---"
POD=$(kubectl get pods -n "$NAMESPACE" -l app=kong-dp -o jsonpath='{.items[0].metadata.name}')
echo "Checking recent logs on pod $POD for access log lines..."
LOG_LINES=$(kubectl logs -n "$NAMESPACE" "$POD" --tail=20 2>/dev/null \
  | grep -E '"GET|"POST|"DELETE' | head -5 || true)
if [[ -z "$LOG_LINES" ]]; then
  check_pass "No access log lines in recent pod logs"
else
  check_warn "No access log lines in recent pod logs" "KONG_PROXY_ACCESS_LOG may not be off: $LOG_LINES"
fi

verify_summary "Lab 4 (Fingerprints)"
