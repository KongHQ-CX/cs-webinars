# Lab 4 — Remove Fingerprints and the Debug Header

**Controls:** #12 Fingerprinting · #16 Nginx access logs · #17 Real IP  
**Time:** ~8 min

## What you'll do
1. Set `headers: "off"` in `values.yaml` to strip Kong's own version/fingerprint headers
   (`Server: kong/x.y.z`, `Via`, `X-Kong-*`). The generic nginx `Server` banner is already
   stripped by Kong's default nginx template — do not also set `nginx_http_server_tokens`,
   which duplicates that directive and breaks nginx config validation.
2. Disable nginx access logs on the DP and configure real-IP trust.

## Steps

```bash
# 0. Set LB_IP, KONNECT_CONTROL_PLANE_ID, KONNECT_PAT, etc. (auto-discovers
#    LB_IP from the cluster where possible; override any var beforehand)
source set-env.sh

# 1. Apply the updated DataPlane release
helm upgrade --install kong-dp kong/kong -n kong -f lab-04-fingerprints/values.yaml --wait

# 2. Verify
bash lab-04-fingerprints/verify.sh

```

## Expected results
- `curl -sk -o /dev/null -D - -H "Host: api.kong-air.example.com" https://$LB_IP/flights | grep -iE 'server|kong|via'`
  → **no output**. (Use a real GET, not `curl -I`/HEAD — `flights-route` only allows `GET`,
  so a HEAD request 404s at the router before any headers are even relevant.)
- Real client IP logged, not the LB IP.
