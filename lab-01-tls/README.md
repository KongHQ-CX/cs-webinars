# Lab 1 — Enforce TLS Across the Data Plane

**Controls:** #1 HTTP disabled · #15 TLS 1.2+ on proxy · CP→DP mTLS channel  
**Time:** ~8 min

## Key concepts

| Channel | Who terminates TLS | Default min version |
|---|---|---|
| Client → DP proxy | Kong DP (nginx) | Set via `env.ssl_protocols` |
| DP → Konnect CP (cluster) | Konnect cloud | TLS 1.2 (hardcoded by Kong) |

> **Admin API in Konnect hybrid mode** — The Admin API is hosted by Konnect cloud,
> not on the DP pod. `admin.enabled` must stay `false` in `values.yaml`.
> All config changes go through the Konnect UI or API.

> **No operator involved** — The DataPlane is a plain `kong/kong` Helm release. The
> chart passes every `env.*` key straight through to a `KONG_*` container env var,
> so `ssl_protocols`/`ssl_ciphers` apply exactly as set, and `proxy.http.enabled: false`
> removes the HTTP listener outright.

## What you'll do
1. Apply `values.yaml` — disables the plain-HTTP listener, sets `ssl_protocols: "TLSv1.2 TLSv1.3"`.
2. Generate a TLS cert via cert-manager for client→proxy TLS termination.
3. Confirm TLS 1.1 handshake fails against the proxy.
4. Confirm the CP→DP cluster mTLS channel is active (cert present, TLS 1.2).

## Steps

```bash
# 1. Issue the TLS cert (base is HTTP-only and does not create this)
kubectl apply -f 00-base/tls/self-signed-issuer.yaml
kubectl wait --for=condition=Ready certificate/kong-labs-ca -n cert-manager --timeout=60s
kubectl apply -f 00-base/tls/proxy-certificate.yaml
kubectl wait --for=condition=Ready certificate/kong-proxy-tls -n kong --timeout=60s

# 2. Apply the updated DataPlane release
helm upgrade --install kong-dp kong/kong -n kong -f lab-01-tls/values.yaml --wait

# 3. Run verification
bash lab-01-tls/verify.sh
```

## Expected results
- `curl http://<LB_IP>/flights` → connection refused (no HTTP listener).
- `openssl s_client -tls1_1` → **handshake failure**.
- `openssl s_client -tls1_2` → **TLSv1.2** negotiated, cert CN = `api.kong-air.example.com`.
- CP→DP mTLS cluster cert present in pod env and Secret `kong-cluster-cert`.
