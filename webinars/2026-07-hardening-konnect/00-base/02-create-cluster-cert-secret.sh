#!/usr/bin/env bash
# Loads the DP client mTLS certificate (cert/tls.cert + cert/tls.key) into a
# Kubernetes Secret. This cert was generated and registered against the
# Konnect Control Plane manually (Konnect UI → Gateway Manager → Control
# Plane → Generate certificate) — no kong-operator/KonnectExtension involved.
set -euo pipefail

NAMESPACE="${NAMESPACE:-kong}"
CERT_DIR="${CERT_DIR:-$(dirname "$0")/cert}"
SECRET_NAME="${SECRET_NAME:-kong-cluster-cert}"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating Secret '$SECRET_NAME' from $CERT_DIR/tls.cert + tls.key"
kubectl create secret tls "$SECRET_NAME" \
  --cert="$CERT_DIR/tls.cert" \
  --key="$CERT_DIR/tls.key" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Done. Reference this Secret in helm/values.yaml as <DP_CERT_SECRET> = $SECRET_NAME"
