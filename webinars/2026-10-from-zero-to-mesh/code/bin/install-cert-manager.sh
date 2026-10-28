#!/usr/bin/env bash
# Install cert-manager on the gateway cluster and get a Let's Encrypt certificate for the
# gateway name with DNS-01 through Cloudflare. The certificate lands in the Secret demo-gateway-tls in
# namespace kong, which the HTTPS listener of the Gateway (stages/03-gateway) reads.
# Usage: install-cert-manager.sh, with CLOUDFLARE_API_TOKEN and TLS_EMAIL in the environment of this command only
#
# Run it before stage 03, or after: the Gateway serves HTTP either way and HTTPS once the Secret exists.
# Env: CLOUDFLARE_API_TOKEN (Zone:Read and DNS:Edit on the zone),
#      TLS_EMAIL (required, Let's Encrypt expiry notices),
#      DNS_NAME (required, the certificate name), DNS_ZONE (required, the Cloudflare zone that holds it),
#      CHART_VERSION (default v1.21.2),
#      TLS_STAGING=1 (use the Let's Encrypt staging server while testing: its certificate is not trusted
#      by browsers, and it has no tight rate limit. The production server allows about 5 identical
#      certificates per week, and every rebuild asks for a new one),
#      RENDER_ONLY=1 (print the filled issuer and certificate, change nothing).
# The token reaches kubectl on stdin only (fill_secret) and is never printed.
# Needs helm and kubectl.
set -euo pipefail
{ set +x; } 2>/dev/null
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$here/../lib/common.sh"

name="${DNS_NAME:-}"
zone="${DNS_ZONE:-}"
chart_version="${CHART_VERSION:-v1.21.2}"
ns="cert-manager"
if [ "${TLS_STAGING:-}" = "1" ]; then
  acme="https://acme-staging-v02.api.letsencrypt.org/directory"
else
  acme="https://acme-v02.api.letsencrypt.org/directory"
fi

require_vars DNS_NAME DNS_ZONE TLS_EMAIL || exit 2
[[ "$name" =~ ^[a-z0-9.-]+$ ]] || { _err "DNS_NAME must be lowercase letters, digits, dots and hyphens"; exit 2; }
[[ "$zone" =~ ^[a-z0-9.-]+$ ]] || { _err "DNS_ZONE must be lowercase letters, digits, dots and hyphens"; exit 2; }
[[ "$chart_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { _err "CHART_VERSION must look like v1.21.2"; exit 2; }
[[ "$TLS_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || { _err "TLS_EMAIL is not an email address"; exit 2; }

# fill <file>: print the manifest with the placeholders replaced. Values passed the checks above.
fill() {
  sed -e "s|__ACME_SERVER__|$acme|" -e "s|__TLS_EMAIL__|$TLS_EMAIL|" -e "s|__DNS_ZONE__|$zone|" -e "s|__DNS_NAME__|$name|" "$1"
}

if [ "${RENDER_ONLY:-}" = "1" ]; then
  fill "$here/../tls/clusterissuer.yaml"
  echo "---"
  fill "$here/../tls/certificate.yaml"
  exit 0
fi

for tool in helm kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { _err "$tool is required and was not found on PATH"; exit 2; }
done
require_vars CLOUDFLARE_API_TOKEN || exit 2
require_ctx_1 || exit 2
cur="$(kubectl config current-context)"
trap 'rm -f "${PINNED_KUBECONFIG:-}"' EXIT
# Pin a private kubeconfig to this context, so a context switch in another terminal cannot send
# the install or the apply to a different cluster.
pin_kubeconfig "$cur" || exit 1

helm upgrade --install cert-manager cert-manager --repo https://charts.jetstack.io --version "$chart_version" \
  --namespace "$ns" --create-namespace -f "$here/../helm/cert-manager.values.yaml" --wait --timeout 5m --kube-context "$cur"

printf '%s' "$CLOUDFLARE_API_TOKEN" | fill_secret "$ns" cloudflare-api-token api-token

# Create the namespace only when it is missing. Never apply a bare namespace manifest here: kubectl apply
# would strip the mesh injection label that stage 03 put on namespace kong, and the next gateway pod
# would start without its sidecar.
kubectl get namespace kong >/dev/null 2>&1 || kubectl create namespace kong >/dev/null
fill "$here/../tls/clusterissuer.yaml" | kubectl apply -f -
kubectl wait --for=condition=Ready clusterissuer/letsencrypt-dns --timeout=120s
fill "$here/../tls/certificate.yaml" | kubectl apply -f -
# DNS-01 waits for the TXT record to spread, so allow a few minutes.
kubectl wait --for=condition=Ready certificate/demo-gateway-tls -n kong --timeout=300s ||
  { _err "the certificate is not Ready: kubectl describe certificate demo-gateway-tls -n kong, then the Order and Challenge objects"; exit 1; }
echo "cert-manager $chart_version installed in $cur, certificate for $name is Ready"
