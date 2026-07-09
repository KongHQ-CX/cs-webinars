#!/usr/bin/env bash
# Installs HashiCorp Vault in standalone mode with in-memory storage and a
# TLS listener certed by the lab CA — same TLS discipline as the Kong proxy
# in Lab 1. Not dev mode: Vault's `-dev-tls` flag always self-generates its
# own throwaway CA on every start, which would force Kong's HCV client to
# re-trust a new CA on every Vault restart. Standalone mode lets the listener
# use our own stable, pre-known lab CA instead — the tradeoff is that
# in-memory storage starts sealed and uninitialized, so this script also
# performs `vault operator init` + unseal on every run (inmem storage does
# not persist across pod restarts, unlike a real backend).
#
# Moved here from lab-02-vault so Vault is already up and seeded by the time
# Lab 2 runs — Lab 2 only registers the backend with Konnect and patches the
# DataPlane, it no longer waits on a fresh Vault install.
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_VERSION="${VAULT_VERSION:-0.28.1}"

kubectl create namespace "$VAULT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Ensuring the lab CA issuer exists (kong-labs-ca-issuer)"
kubectl apply -f "$BASE_DIR/tls/self-signed-issuer.yaml"
kubectl wait --for=condition=Ready certificate/kong-labs-ca -n cert-manager --timeout=60s

echo "==> Issuing Vault server TLS certificate (Secret 'vault-server-tls')"
kubectl apply -f "$BASE_DIR/vault/vault-tls-certificate.yaml"
kubectl wait --for=condition=Ready certificate/vault-server-tls -n "$VAULT_NAMESPACE" --timeout=60s

# Kong's HCV client (in the 'kong' namespace) needs the lab CA cert to verify
# Vault's server certificate. cert-manager Secrets can't be mounted
# cross-namespace, so copy the CA cert into 'kong' as a plain Secret —
# ca.crt only, no private key material involved.
echo "==> Copying lab CA cert into 'kong' namespace as Secret 'kong-labs-ca'"
CA_CRT=$(kubectl get secret kong-labs-ca-secret -n cert-manager -o jsonpath='{.data.ca\.crt}')
kubectl create secret generic kong-labs-ca \
  --from-literal=ca.crt="$(echo "$CA_CRT" | base64 -d)" \
  -n kong \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

echo "==> Installing Vault ${VAULT_VERSION} — standalone mode, in-memory storage, HTTPS listener"
helm upgrade --install vault hashicorp/vault \
  --namespace "$VAULT_NAMESPACE" \
  --version "$VAULT_VERSION" \
  --set "server.dev.enabled=false" \
  --set "injector.enabled=false" \
  --set "server.standalone.enabled=true" \
  --set "server.volumes[0].name=vault-server-tls" \
  --set "server.volumes[0].secret.secretName=vault-server-tls" \
  --set "server.volumeMounts[0].name=vault-server-tls" \
  --set "server.volumeMounts[0].mountPath=/vault/tls" \
  --set "server.volumeMounts[0].readOnly=true" \
  --set-string "server.standalone.config=
    listener \"tcp\" {
      address       = \"0.0.0.0:8200\"
      tls_disable   = false
      tls_cert_file = \"/vault/tls/tls.crt\"
      tls_key_file  = \"/vault/tls/tls.key\"
    }
    storage \"inmem\" {}
  " \
  --wait

echo "==> Vault pod status"
kubectl get pods -n "$VAULT_NAMESPACE"
kubectl wait --for=condition=PodScheduled pod/vault-0 -n "$VAULT_NAMESPACE" --timeout=60s

VAULT_ADDR_LOCAL="https://127.0.0.1:8200"
vault_exec() {
  kubectl exec -n "$VAULT_NAMESPACE" vault-0 -- \
    env VAULT_ADDR="$VAULT_ADDR_LOCAL" VAULT_SKIP_VERIFY=true "$@"
}

echo "==> Waiting for the Vault API to come up"
for i in $(seq 1 30); do
  # `vault status` exits 0 (unsealed) or 2 (sealed/uninitialized but reachable) —
  # both mean the API is up. Only a connection failure means "not ready yet".
  STATUS_OUT=$(vault_exec vault status 2>&1) && break
  if echo "$STATUS_OUT" | grep -qi "Sealed\|Initialized"; then
    break
  fi
  sleep 2
done

INIT_STATUS=$(vault_exec vault status -format=json 2>/dev/null || echo '{}')
INITIALIZED=$(echo "$INIT_STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('initialized', False))" 2>/dev/null || echo "False")

UNSEAL_KEY_FILE="$(dirname "$0")/.vault-unseal-key"

if [[ "$INITIALIZED" != "True" ]]; then
  echo "==> Initializing Vault (in-memory storage starts sealed/uninitialized on every pod start)"
  INIT_OUT=$(vault_exec vault operator init -key-shares=1 -key-threshold=1 -format=json)
  echo "$INIT_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print('Root token:', d['root_token']); print('Unseal key:', d['unseal_keys_b64'][0])"

  ROOT_TOKEN=$(echo "$INIT_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")
  UNSEAL_KEY=$(echo "$INIT_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['unseal_keys_b64'][0])")

  echo "$UNSEAL_KEY" > "$UNSEAL_KEY_FILE"
  kubectl create secret generic vault-root-token \
    --from-literal=token="$ROOT_TOKEN" \
    -n "$VAULT_NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

  echo "==> Unsealing Vault"
  vault_exec vault operator unseal "$UNSEAL_KEY"
else
  echo "==> Vault already initialized — unsealing with saved key"
  UNSEAL_KEY=$(cat "$UNSEAL_KEY_FILE" 2>/dev/null || echo "")
  if [[ -z "$UNSEAL_KEY" ]]; then
    echo "  FAIL: Vault reports initialized but no local unseal key found at $UNSEAL_KEY_FILE"
    echo "        In-memory storage means Vault must be re-initialized — delete the vault-0 pod and re-run this script."
    exit 1
  fi
  vault_exec vault operator unseal "$UNSEAL_KEY"
fi

ROOT_TOKEN=$(kubectl get secret vault-root-token -n "$VAULT_NAMESPACE" -o jsonpath='{.data.token}' | base64 -d)

echo ""
echo "==> Vault ready. Root token stored in Secret 'vault-root-token' (namespace $VAULT_NAMESPACE)."
echo "    Access via: kubectl exec -n $VAULT_NAMESPACE vault-0 -- env VAULT_ADDR=$VAULT_ADDR_LOCAL VAULT_SKIP_VERIFY=true VAULT_TOKEN=$ROOT_TOKEN vault status"
