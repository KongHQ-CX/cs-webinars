# Lab 2 — Zero Plaintext Credentials with Vault

**Controls:** #2 LDAP credentials · #3 Consumer credential secrets · #8 key-auth encrypted  
**Time:** ~5 min

> **Vault is already running** — HashiCorp Vault (HTTPS listener, TLS cert from the lab CA)
> is installed and seeded as part of base setup (`00-base/03-install-vault.sh` and
> `00-base/04-vault-init.sh`), so the Secret `kong-vault-approle` this lab's `values.yaml`
> references already exists. This lab only registers the Vault backend with Konnect and
> switches the DataPlane over to use it.

## What you'll do
1. Register the Vault backend in Konnect via the Admin API (`protocol: https`).
2. Apply `values.yaml` — Kong's HCV backend env vars, with TLS verification enabled
   against the lab CA.
3. Replace any plugin credentials with `{vault://kongair-vault/...}` references
   (`kongair-vault` is the vault's Konnect *prefix*; `hcv` is reserved by Kong and
   can't be reused as a prefix — see `01-register-vault-konnect.sh`).

## Steps

```bash
# 1. Register vault backend in Konnect (Vault + AppRole Secret already exist from base setup)
export VAULT_ADDR="https://vault.vault.svc:8200"
bash lab-02-vault/01-register-vault-konnect.sh

# 2. Apply the updated DataPlane release with HCV env vars
helm upgrade --install kong-dp kong/kong -n kong -f lab-02-vault/values.yaml --wait

# 3. Verify
bash lab-02-vault/verify.sh
```

## Expected results
- `GET /core-entities/vaults` returns the `hcv` vault entry with `protocol: https`.
- `openssl s_client -connect <vault-pod-ip>:8200` negotiates TLS and presents a cert
  signed by `kong-labs-ca`.
- No plaintext secrets appear in `kubectl exec ... -- env | grep -iE 'key|secret|pass|token'`.
- Plugin config shows `{vault://kongair-vault/kong-air/key-auth}` references, not raw values.
