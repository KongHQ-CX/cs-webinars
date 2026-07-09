#!/usr/bin/env bash
# Installs cert-manager — used to issue the proxy's HTTPS server certificate.
# No Gateway API CRDs or Kong CRDs are required: routing (Services/Routes) is
# created directly in Konnect via the Admin API, not via Kubernetes objects.
set -euo pipefail

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.16.3}"

echo "==> Installing cert-manager ${CERT_MANAGER_VERSION}"
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

echo "==> Waiting for cert-manager to be ready"
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s
kubectl rollout status deployment/cert-manager-webhook -n cert-manager --timeout=120s

echo "==> Prerequisites ready"
