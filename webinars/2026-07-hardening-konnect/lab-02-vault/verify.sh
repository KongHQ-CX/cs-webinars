#!/usr/bin/env bash
# Lab 2 verification — Vault integration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/verify-common.sh"

: "${KONNECT_PAT:=<type your Konnect PAT>}"
: "${KONNECT_CONTROL_PLANE_ID:=<type your Konnect Control plane ID>}"

KONNECT_REGION="${KONNECT_REGION:-in}"
BASE_URL="https://${KONNECT_REGION}.api.konghq.com/v2/control-planes/${KONNECT_CONTROL_PLANE_ID}/core-entities"
AUTH="Authorization: Bearer ${KONNECT_PAT}"
NAMESPACE="${NAMESPACE:-kong}"

VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"

echo "--- Vault listener is HTTPS, not plaintext HTTP ---"
POD=$(kubectl get pods -n "$NAMESPACE" -l app=kong-dp -o jsonpath='{.items[0].metadata.name}')
VAULT_TLS=$(kubectl exec -n "$NAMESPACE" "$POD" -- \
  sh -c "echo Q | openssl s_client -connect vault.${VAULT_NAMESPACE}.svc:8200 -servername vault.${VAULT_NAMESPACE}.svc 2>&1" || true)
if echo "$VAULT_TLS" | grep -q "CONNECTED\|Cipher"; then
  check_pass "Vault listener negotiates TLS on :8200"
  echo "$VAULT_TLS" | grep -E 'subject=|issuer=' | sed 's/^/  /' || true
else
  check_fail "Vault listener negotiates TLS on :8200" "could not negotiate TLS"
fi

echo ""
echo "--- Control #2/#3/#8: Kong HCV client configured for HTTPS ---"
HCV_PROTOCOL=$(kubectl exec -n "$NAMESPACE" "$POD" -- env 2>/dev/null \
  | grep '^KONG_VAULT_HCV_PROTOCOL=' | cut -d= -f2- || echo "")
if [[ "$HCV_PROTOCOL" == "https" ]]; then
  check_pass "KONG_VAULT_HCV_PROTOCOL=https"
else
  check_fail "KONG_VAULT_HCV_PROTOCOL=https" "got '${HCV_PROTOCOL}'"
fi

echo ""
echo "--- Control #2/#3/#8: Zero plaintext credentials in DP env ---"
echo "Checking env on pod: $POD"

# A credential-shaped var name (api_key/password/secret/jwt_secret) is only a
# violation if its VALUE looks like an inline secret, not a mounted file path
# (e.g. KONG_CLUSTER_CERT=/etc/secrets/kong-cluster-cert/tls.crt is fine) or a
# reference to a vault/AppRole identifier used to authenticate *to* Vault
# (KONG_VAULT_HCV_APPROLE_SECRET_ID — matching is case-insensitive since env
# var names are uppercase but the exclusion terms are written lowercase).
PLAINTEXT=$(kubectl exec -n "$NAMESPACE" "$POD" -- env \
  | grep -iE '(api_key|password|jwt_secret|secret)=' \
  | grep -viE 'vault|hcv|approle' \
  | awk -F= '$2 !~ /^\// {print}' || true)

if [[ -z "$PLAINTEXT" ]]; then
  check_pass "No plaintext credential env vars found"
else
  check_fail "No plaintext credential env vars found" "$PLAINTEXT"
fi

echo ""
echo "--- Vault backend registered in Konnect ---"
VAULTS=$(curl -sf "${BASE_URL}/vaults" -H "$AUTH")
echo "$VAULTS" | python3 -m json.tool
VAULT_COUNT=$(echo "$VAULTS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))")
if [[ "$VAULT_COUNT" -ge 1 ]]; then
  check_pass "$VAULT_COUNT vault backend(s) registered"
else
  check_fail "Vault backend(s) registered in Konnect" "none found"
fi

echo ""
echo "--- Consumer key references vault syntax ---"
KEYS=$(curl -sf "${BASE_URL}/key-auths" -H "$AUTH" 2>/dev/null || echo '{"data":[]}')
KEY_RESULTS=$(echo "$KEYS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for k in d.get('data', []):
    val = k.get('key','')
    if '{vault://' in val:
        print(f'PASS\tkey uses vault ref: {val}')
    else:
        print(f'WARN\tkey is plaintext: {val[:20]}...')
")
while IFS=$'\t' read -r status detail; do
  [[ -z "$status" ]] && continue
  if [[ "$status" == "PASS" ]]; then
    check_pass "$detail"
  else
    check_warn "$detail"
  fi
done <<< "$KEY_RESULTS"

verify_summary "Lab 2 (Vault)"
