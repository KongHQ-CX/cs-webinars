# Lab 5 — Rate Limiting, Audit Logs, and DP Health
**This lab is WIP**
**Controls:** #24 Rate limiting · #19 Audit logs · #4/#5 DP health monitoring  
**Time:** ~8 min

## What you'll do
1. Deploy Redis and create a global rate-limiting plugin (200 req/min).
2. Burst-test with 210 requests and confirm 429 from request 201.
3. Configure the Konnect audit log SIEM webhook.
4. Make a config change and verify it appears in audit logs.
5. Query DP node health.

## Steps

```bash
export KONNECT_PAT="<your-admin-PAT>"
export KONNECT_CONTROL_PLANE_ID="<cp-uuid>"
export LB_IP="<GKE LoadBalancer IP>"
export SIEM_WEBHOOK_URL="https://your-siem.example.com/ingest"

# 1. Deploy Redis
kubectl apply -f redis.yaml
kubectl rollout status deployment/redis -n kong --timeout=60s

# 2. Create global rate-limiting plugin
bash rate-limiting-plugin.sh

# 3. Configure audit log webhook
bash audit-log-webhook.sh

# 4. Burst test (run after plugin propagates ~30s)
bash burst-test.sh

# 5. Verify everything
bash verify.sh
```

## Expected results
- Requests 1–200 return `HTTP 200`.
- Requests 201–210 return `HTTP 429` with `Retry-After` header.
- `GET /v2/audit-logs` shows the plugin-create event.
- All DP nodes show `status: connected` in the health API.
