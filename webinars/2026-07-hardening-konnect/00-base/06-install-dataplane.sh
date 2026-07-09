#!/usr/bin/env bash
# Installs the Kong Gateway DataPlane via the kong/kong Helm chart (Konnect
# hybrid mode). No operator, no CRDs — this is the only thing that manages
# the DataPlane workload.
#
# Prerequisites:
#   - Secret 'kong-cluster-cert' must exist (02-create-cluster-cert-secret.sh).
#   - helm/values.yaml must point at your Control Plane's cluster_control_plane
#     / cluster_telemetry_endpoint hostnames (Konnect UI → Gateway Manager →
#     Control Plane → Connectivity).
#
# Base installs HTTP-only — Secret 'kong-proxy-tls' is only required starting
# in Lab 1, which switches the DataPlane to HTTPS-only.
set -euo pipefail

NAMESPACE="${NAMESPACE:-kong}"
RELEASE="${RELEASE_NAME:-kong-dp}"
VALUES_FILE="${VALUES_FILE:-$(dirname "$0")/helm/values.yaml}"

helm repo add kong https://charts.konghq.com >/dev/null
helm repo update >/dev/null

echo "==> Installing DataPlane release '$RELEASE' via Helm (namespace: $NAMESPACE)"
helm upgrade --install "$RELEASE" kong/kong \
  --namespace "$NAMESPACE" \
  -f "$VALUES_FILE" \
  --wait

echo "==> DataPlane pods"
kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE"
