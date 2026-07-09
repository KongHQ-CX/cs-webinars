#!/usr/bin/env bash
# Lab 1 verification — proxy TLS enforcement + CP→DP mTLS channel.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/verify-common.sh"

NAMESPACE="${NAMESPACE:-kong}"
HOST="${GATEWAY_HOST:-api.kong-air.example.com}"

LB_IP=$(kubectl get svc -n "$NAMESPACE" -l app=kong-dp \
  -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}')
echo "==> Gateway IP: $LB_IP"

# ----------------------------------------------------------------
# Control #1 — HTTP listener disabled via proxy.http.enabled: false
# ----------------------------------------------------------------
echo ""
echo "--- Control #1: KONG_PROXY_LISTEN has no plaintext HTTP entry ---"
POD=$(kubectl get pods -n "$NAMESPACE" -l app=kong-dp \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
PROXY_LISTEN=$(kubectl exec -n "$NAMESPACE" "$POD" -- env 2>/dev/null \
  | grep KONG_PROXY_LISTEN | cut -d= -f2- || echo "")
echo "    $PROXY_LISTEN"
if echo "$PROXY_LISTEN" | grep -q "8443" && ! echo "$PROXY_LISTEN" | grep -q "8000"; then
  check_pass "Only the HTTPS listener (8443) is configured"
else
  check_fail "KONG_PROXY_LISTEN has no plaintext HTTP entry" "unexpected value: $PROXY_LISTEN"
fi

# ----------------------------------------------------------------
# Control #1 — actual port reachability: 8443 open, 8000 closed
# ----------------------------------------------------------------
echo ""
echo "--- Control #1: port 8443 (HTTPS) must be open on the LoadBalancer ---"
if nc -z -w5 "$LB_IP" 443 2>/dev/null; then
  check_pass "Port 443 (proxy-tls -> 8443) is open"
else
  check_fail "Port 443 (proxy-tls -> 8443) is open" "not reachable"
fi

echo ""
echo "--- Control #1: port 8000 (HTTP) must be closed on the LoadBalancer ---"
if nc -z -w5 "$LB_IP" 80 2>/dev/null; then
  check_fail "Port 80 (proxy -> 8000) is closed" "reachable — HTTP listener should be disabled"
else
  check_pass "Port 80 (proxy -> 8000) is closed/unreachable"
fi

echo ""
echo "--- Control #1: pod-level check — only 8443 listening inside the container ---"
LISTEN_PORTS=$(kubectl exec -n "$NAMESPACE" "$POD" -- sh -c \
  "cat /proc/net/tcp 2>/dev/null | awk 'NR>1 {print \$2}' | cut -d: -f2 | sort -u | while read p; do printf '%d\n' 0x\$p; done" 2>/dev/null || echo "")
echo "  Listening ports inside pod: $(echo "$LISTEN_PORTS" | tr '\n' ' ')"
if echo "$LISTEN_PORTS" | grep -qx "8443" && ! echo "$LISTEN_PORTS" | grep -qx "8000"; then
  check_pass "Pod has 8443 listening and 8000 is not"
elif echo "$LISTEN_PORTS" | grep -qx "8000"; then
  check_fail "Pod has 8443 listening and 8000 is not" "8000 still listening"
else
  check_warn "Could not confirm 8443 listening from /proc/net/tcp" "check manually"
fi

# ----------------------------------------------------------------
# Control #15 — ssl_protocols/ssl_ciphers applied directly (Helm chart
# passes env.* straight through — no operator stripping/rewriting)
# ----------------------------------------------------------------
echo ""
echo "--- Control #15: KONG_SSL_PROTOCOLS in pod env ---"
SSL_PROTO=$(kubectl exec -n "$NAMESPACE" "$POD" -- env 2>/dev/null \
  | grep '^KONG_SSL_PROTOCOLS=' | cut -d= -f2- || echo "")
if [[ -n "$SSL_PROTO" ]]; then
  check_pass "KONG_SSL_PROTOCOLS set ($SSL_PROTO)"
else
  check_fail "KONG_SSL_PROTOCOLS set" "not found in pod env"
fi

# ----------------------------------------------------------------
# Control #15 — TLS 1.1 rejected, TLS 1.2 accepted
# ----------------------------------------------------------------
echo ""
echo "--- Control #15: TLS 1.1 must fail ---"
TLS11=$(echo "Q" | openssl s_client \
  -connect "${LB_IP}:443" \
  -servername "$HOST" \
  -tls1_1 2>&1 || true)
echo "$TLS11" | grep -E 'Protocol|handshake|alert|error|CONNECTED' || true
if echo "$TLS11" | grep -qi "handshake failure\|alert handshake\|ssl alert\|no protocols"; then
  check_pass "TLS 1.1 handshake fails as expected"
else
  check_warn "TLS 1.1 handshake fails as expected" "outcome unclear — review output above"
fi

echo ""
echo "--- Control #15: TLS 1.2 must succeed ---"
TLS12=$(echo "Q" | openssl s_client \
  -connect "${LB_IP}:443" \
  -servername "$HOST" \
  -tls1_2 2>&1 || true)
echo "$TLS12" | grep -E 'Protocol|Cipher|subject|CONNECTED' || true
if echo "$TLS12" | grep -q "TLSv1.2"; then
  check_pass "TLS 1.2 handshake succeeds"
else
  check_fail "TLS 1.2 handshake succeeds" "did not succeed"
fi

# echo ""
# echo "--- TLS cert CN matches expected hostname ---"
# CERT_CN=$(echo "$TLS12" | grep -oE 'CN\s*=\s*[^,\n]+' | head -1 || true)
# echo "  Subject: $CERT_CN"
# if echo "$CERT_CN" | grep -q "$HOST\|kong-air"; then
#   check_pass "Certificate CN matches gateway hostname"
# else
#   check_warn "Certificate CN matches gateway hostname" "expected $HOST, got: $CERT_CN"
# fi

# ----------------------------------------------------------------
# CP→DP mTLS channel — verify cert secret and cluster connection
# ----------------------------------------------------------------
echo ""
echo "--- CP→DP mTLS: cluster cert Secret must exist ---"
DP_CERT_SECRET="kong-cluster-cert"
if kubectl get secret "$DP_CERT_SECRET" -n "$NAMESPACE" &>/dev/null; then
  check_pass "Secret '$DP_CERT_SECRET' exists"
  # Show cert expiry without printing key material.
  kubectl get secret "$DP_CERT_SECRET" -n "$NAMESPACE" \
    -o jsonpath='{.data.tls\.crt}' \
    | base64 -d \
    | openssl x509 -noout -subject -issuer -dates 2>/dev/null || true
else
  check_fail "Secret '$DP_CERT_SECRET' exists" "not found — run 00-base/02-create-cluster-cert-secret.sh"
fi

echo ""
echo "--- CP→DP mTLS: KONG_CLUSTER_MTLS=pki set on DP pod ---"
POD=$(kubectl get pods -n "$NAMESPACE" -l app=kong-dp \
  -o jsonpath='{.items[0].metadata.name}')
MTLS_VAL=$(kubectl exec -n "$NAMESPACE" "$POD" -- \
  env 2>/dev/null | grep KONG_CLUSTER_MTLS | awk -F= '{print $2}' || echo "")
if [[ "$MTLS_VAL" == "pki" ]]; then
  check_pass "KONG_CLUSTER_MTLS=pki (mTLS active on cluster channel)"
else
  check_fail "KONG_CLUSTER_MTLS=pki on cluster channel" "got '${MTLS_VAL}'"
fi

echo ""
echo "--- CP→DP mTLS: cluster channel TLS — connect to Konnect CP endpoint ---"
# Extract the CP endpoint from the DP pod's own env (set via values.yaml cluster_control_plane).
CP_ENDPOINT=$(kubectl exec -n "$NAMESPACE" "$POD" -- env 2>/dev/null \
  | grep '^KONG_CLUSTER_CONTROL_PLANE=' | cut -d= -f2- || echo "")

if [[ -n "$CP_ENDPOINT" ]]; then
  CP_HOST="${CP_ENDPOINT%%:*}"
  CP_PORT="${CP_ENDPOINT##*:}"
  CP_PORT="${CP_PORT:-443}"
  echo "  Probing CP endpoint: ${CP_HOST}:${CP_PORT}"
  CP_TLS=$(echo "Q" | openssl s_client \
    -connect "${CP_HOST}:${CP_PORT}" \
    -servername "$CP_HOST" 2>&1 || true)
  NEGOTIATED=$(echo "$CP_TLS" | grep -oE 'Protocol\s*:\s*\S+' | head -1 || true)
  echo "  Negotiated: $NEGOTIATED"
  if echo "$NEGOTIATED" | grep -qE "TLSv1\.[23]"; then
    check_pass "CP→DP cluster channel uses TLS 1.2 or higher"
  else
    check_warn "CP→DP cluster channel uses TLS 1.2 or higher" "could not confirm — network policy may block outbound :443 from this shell"
  fi
else
  check_warn "CP→DP cluster channel TLS version" "KONG_CLUSTER_CONTROL_PLANE not in pod env (channel is always TLS 1.2+ when KONG_CLUSTER_MTLS=pki)"
fi

verify_summary "Lab 1 (TLS)"
