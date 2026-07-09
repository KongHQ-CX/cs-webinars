#!/usr/bin/env bash
# Seeds Kong-Air secrets into Vault and creates a read-only policy for Kong DP.
# Moved here from lab-02-vault so Vault is already seeded and the AppRole
# Secret exists by the time any lab needs it.
#
# Run after 03-install-vault.sh, which initializes+unseals Vault (standalone
# mode, in-memory storage) and stores the root token in Secret 'vault-root-token'.
set -euo pipefail

VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_POD="vault-0"

ROOT_TOKEN=$(kubectl get secret vault-root-token -n "$VAULT_NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")
if [[ -z "$ROOT_TOKEN" ]]; then
  echo "FAIL: Secret 'vault-root-token' not found — run 03-install-vault.sh first"
  exit 1
fi

# Vault's listener is HTTPS-only (see 03-install-vault.sh). The server cert is
# signed by the lab CA, which isn't in the pod's system trust store, so the
# CLI needs VAULT_SKIP_VERIFY here. Kong's own HCV client instead trusts the
# CA explicitly via vault_hcv_tls_verify + a mounted CA bundle — see each
# lab's values.yaml.
vault_exec() {
  kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- \
    env VAULT_TOKEN="$ROOT_TOKEN" VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true "$@"
}

echo "==> Enabling KV v2 secrets engine at kv/"
vault_exec vault secrets enable -path=kv kv-v2 2>/dev/null || echo "kv already enabled"

echo "==> Writing Kong-Air API key secret"
vault_exec vault kv put kv/kong-air/key-auth \
  api_key="super-secret-key-$(openssl rand -hex 8)"

echo "==> Writing LDAP bind credentials"
vault_exec vault kv put kv/kong-air/ldap \
  bind_password="ldap-bind-$(openssl rand -hex 8)"

echo "==> Writing consumer credential"
vault_exec vault kv put kv/kong-air/consumer-jwt \
  secret="jwt-consumer-secret-$(openssl rand -hex 16)"

echo "==> Creating Kong read-only policy"
# `vault policy write kong-dp -` reads the policy body from stdin, but
# `kubectl exec` does not forward local stdin unless run with -i — piping a
# heredoc through it silently sends Vault an empty body. Write the policy to
# a file inside the pod instead and point the CLI at that.
kubectl exec -i -n "$VAULT_NAMESPACE" "$VAULT_POD" -- sh -c 'cat > /tmp/kong-dp-policy.hcl' <<'POLICY'
path "kv/data/kong-air/*" {
  capabilities = ["read"]
}
POLICY
vault_exec vault policy write kong-dp /tmp/kong-dp-policy.hcl

echo "==> Creating AppRole for Kong DP"
vault_exec vault auth enable approle 2>/dev/null || echo "approle already enabled"
vault_exec vault write auth/approle/role/kong-dp \
  token_policies="kong-dp" \
  token_ttl=1h \
  token_max_ttl=4h

ROLE_ID=$(vault_exec vault read -field=role_id auth/approle/role/kong-dp/role-id)
SECRET_ID=$(vault_exec vault write -f -field=secret_id auth/approle/role/kong-dp/secret-id)

echo ""
echo "==> AppRole credentials (store these in Kubernetes Secrets):"
echo "    KONG_VAULT_HCV_APPROLE_ROLE_ID:   $ROLE_ID"
echo "    KONG_VAULT_HCV_APPROLE_SECRET_ID: $SECRET_ID"
echo ""

# Store in a Kubernetes secret for the DP patch to reference.
kubectl create secret generic kong-vault-approle \
  --from-literal=role_id="$ROLE_ID" \
  --from-literal=secret_id="$SECRET_ID" \
  -n kong \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Vault init complete. Secret 'kong-vault-approle' created in kong namespace."
