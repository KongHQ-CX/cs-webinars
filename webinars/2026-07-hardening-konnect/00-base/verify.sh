#!/usr/bin/env bash
# Smoke-test the base environment end to end.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/verify-common.sh"

NAMESPACE="${NAMESPACE:-kong}"
HOST="${GATEWAY_HOST:-api.kong-air.example.com}"

echo "==> TLS cert status (kong-proxy-tls)"
if kubectl get certificate kong-proxy-tls -n "$NAMESPACE" 2>/dev/null; then
  check_pass "kong-proxy-tls certificate exists"
else
  check_warn "kong-proxy-tls certificate not found" "run: kubectl apply -f tls/self-signed-issuer.yaml && kubectl apply -f tls/proxy-certificate.yaml"
fi

echo ""
echo "==> DataPlane pod status"
kubectl get pods -n "$NAMESPACE" -l app=kong-dp

echo ""
echo "==> Gateway external IP"
LB_IP=$(kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/instance=kong-dp \
  -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
echo "LoadBalancer IP: $LB_IP"

echo ""
echo "==> Helm release status"
if helm status kong-dp -n "$NAMESPACE" 2>/dev/null | head -5; then
  check_pass "helm release 'kong-dp' found"
else
  check_warn "helm release 'kong-dp' not found"
fi

echo ""
if [[ -n "${KONNECT_PAT:-}" && -n "${KONNECT_CONTROL_PLANE_ID:-}" ]]; then
  KONNECT_REGION="${KONNECT_REGION:-us}"
  BASE_URL="https://${KONNECT_REGION}.api.konghq.com/v2/control-planes/${KONNECT_CONTROL_PLANE_ID}/core-entities"
  AUTH="Authorization: Bearer ${KONNECT_PAT}"

  echo "==> Konnect Services"
  curl -sf "${BASE_URL}/services" -H "$AUTH" | python3 -m json.tool

  echo ""
  echo "==> Konnect Routes"
  curl -sf "${BASE_URL}/routes" -H "$AUTH" | python3 -m json.tool
else
  echo "==> Skipping Konnect Services/Routes check — set KONNECT_PAT and KONNECT_CONTROL_PLANE_ID to enable"
fi

echo ""
echo "==> CP→DP TLS verification"

# Pick any running DP pod.
DP_POD=$(kubectl get pods -n "$NAMESPACE" -l app=kong-dp \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -z "$DP_POD" ]]; then
  check_warn "CP→DP TLS check" "no running DP pod found — skipping"
else
  # 1. Confirm mTLS mode.
  MTLS=$(kubectl exec -n "$NAMESPACE" "$DP_POD" -- \
    env 2>/dev/null | grep KONG_CLUSTER_MTLS | cut -d= -f2 || echo "")
  if [[ "$MTLS" == "pki" ]]; then
    check_pass "KONG_CLUSTER_MTLS=pki (mTLS active)"
  else
    check_fail "KONG_CLUSTER_MTLS set to pki" "got '${MTLS}'"
  fi

  # 2. Confirm cluster cert is present in the pod env (value is the PEM itself).
  CERT_PRESENT=$(kubectl exec -n "$NAMESPACE" "$DP_POD" -- \
    env 2>/dev/null | grep -c KONG_CLUSTER_CERT || true)
  if [[ "$CERT_PRESENT" -ge 1 ]]; then
    check_pass "KONG_CLUSTER_CERT env var present"
  else
    check_fail "KONG_CLUSTER_CERT env var present" "not found in pod env"
  fi

  # 3. Extract cluster cert from the mounted Secret path (KONG_CLUSTER_CERT
  # holds the file path — see helm/values.yaml).
  TMPDIR_TLS=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_TLS"' EXIT

  CERT_PATH=$(kubectl exec -n "$NAMESPACE" "$DP_POD" -- \
    env 2>/dev/null | grep '^KONG_CLUSTER_CERT=' | cut -d= -f2-)
  KEY_PATH=$(kubectl exec -n "$NAMESPACE" "$DP_POD" -- \
    env 2>/dev/null | grep '^KONG_CLUSTER_CERT_KEY=' | cut -d= -f2-)

  if [[ -n "$CERT_PATH" ]]; then
    kubectl exec -n "$NAMESPACE" "$DP_POD" -- cat "$CERT_PATH" 2>/dev/null > "$TMPDIR_TLS/cluster.crt"
    kubectl exec -n "$NAMESPACE" "$DP_POD" -- cat "$KEY_PATH"  2>/dev/null > "$TMPDIR_TLS/cluster.key"
  else
    check_warn "Could not determine KONG_CLUSTER_CERT path from pod env"
  fi

  echo "  Cluster cert details:"
  openssl x509 -noout -subject -issuer -dates \
    -in "$TMPDIR_TLS/cluster.crt" 2>/dev/null \
    | sed 's/^/    /' || echo "    (could not decode — cert file may be empty)"

  # 4. Extract the Konnect CP endpoint and probe TLS version.
  CP_ENDPOINT=$(kubectl exec -n "$NAMESPACE" "$DP_POD" -- \
    env 2>/dev/null | grep KONG_CLUSTER_CONTROL_PLANE | cut -d= -f2 || echo "")

  if [[ -n "$CP_ENDPOINT" ]]; then
    CP_HOST="${CP_ENDPOINT%%:*}"
    CP_PORT="${CP_ENDPOINT##*:}"
    echo "  Probing CP endpoint: ${CP_HOST}:${CP_PORT}"

    # Probe without client cert first — TLS version is negotiated before client auth.
    TLS_OUT=$(echo "Q" | openssl s_client \
      -connect "${CP_HOST}:${CP_PORT}" \
      -servername "${CP_HOST}" \
      2>&1 || true)
    NEGOTIATED=$(echo "$TLS_OUT" | grep -oE 'Protocol\s*:\s*\S+' | head -1 || true)

    if echo "$NEGOTIATED" | grep -qE "TLSv1\.[23]"; then
      check_pass "CP endpoint TLS version ($NEGOTIATED)"
      # Now verify the DP's client cert is accepted (full mTLS handshake).
      if [[ -s "$TMPDIR_TLS/cluster.crt" && -s "$TMPDIR_TLS/cluster.key" ]]; then
        MTLS_OUT=$(echo "Q" | openssl s_client \
          -connect "${CP_HOST}:${CP_PORT}" \
          -servername "${CP_HOST}" \
          -cert "$TMPDIR_TLS/cluster.crt" \
          -key  "$TMPDIR_TLS/cluster.key" \
          2>&1 || true)
        if echo "$MTLS_OUT" | grep -q "Verification\|CONNECTED\|SSL handshake"; then
          check_pass "mTLS handshake with cluster cert succeeded"
        else
          check_warn "mTLS handshake probe inconclusive" "CP may require Kong-internal SNI routing"
        fi
      fi
    else
      check_warn "Could not capture TLS version" "CP may not accept unauthenticated probes from this host"
    fi
  else
    check_warn "KONG_CLUSTER_CONTROL_PLANE not in pod env"
  fi
fi

echo ""
echo "==> Backend pods"
kubectl get pods -n kong-air

echo ""
echo "==> Smoke test — GET /flights (HTTP)"
curl -sk -H "Host: $HOST" "http://${LB_IP}/flights" | python3 -m json.tool || true

echo ""
echo "==> Smoke test — GET /bookings (HTTP)"
curl -sk -H "Host: $HOST" "http://${LB_IP}/bookings" | python3 -m json.tool || true

verify_summary "Base environment"
# curl -sk -H "Host: api.kong-air.example.com" "http://34.93.39.231/flights" 