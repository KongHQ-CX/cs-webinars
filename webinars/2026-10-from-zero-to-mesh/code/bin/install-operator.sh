#!/usr/bin/env bash
# Install Kong Operator with Helm on the gateway cluster (zone 1) with the Konnect controller on.
# Usage: install-operator.sh <install|ready>
#
# Prerequisites: the active context is <install|ready>-1 (the Operator runs in zone 1 only). The
# gateway stage (stages/03-gateway) needs this step first, then the token Secret in namespace kong
# (OPERATOR_SECRET_NAMESPACE=kong bin/fill-from-env.sh operator).
#
# Optional: CHART_VERSION (default 1.4.2). Needs helm, kubectl, jq and yq (mikefarah, v4).
#
# The script fails closed. Before it installs, it renders the chart with helm template and refuses to
# go on unless the rendered Operator Deployment sets ENABLE_CONTROLLER_KONNECT=true and uses an image
# tag that names a full version. After the install it reads the live Deployment and checks the same
# environment variable again.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$here/../lib/common.sh"

CHART_REPO="https://charts.konghq.com"
OPERATOR_NS="kong-system"
usage="usage: install-operator.sh <install|ready>"
[ "$#" -eq 1 ] || { echo "$usage" >&2; exit 2; }
set_name="$1"
case "$set_name" in install | ready) ;; *) echo "$usage" >&2; exit 2 ;; esac
chart_version="${CHART_VERSION:-1.4.2}"
[[ $chart_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { _err "CHART_VERSION must look like 1.4.2"; exit 2; }
for tool in helm kubectl jq yq; do
  command -v "$tool" >/dev/null 2>&1 || { _err "$tool is required and was not found on PATH"; exit 2; }
done

require_ctx "$set_name" || exit 2
cur="$(kubectl config current-context)"
[ "$cur" = "$set_name-1" ] || { _err "the Operator runs in zone 1 only: switch to $set_name-1 (active: $cur)"; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; rm -f "${PINNED_KUBECONFIG:-}"' EXIT
# Pin a private kubeconfig to this context, so a context switch in another terminal cannot
# send the install or the check to a different cluster.
pin_kubeconfig "$cur" || exit 1

# env_is_true <json-lines of Deployments>: some container sets ENABLE_CONTROLLER_KONNECT to "true".
# Chart 1.4.2 renders the value env.ENABLE_CONTROLLER_KONNECT as KONG_OPERATOR_ENABLE_CONTROLLER_KONNECT
# (seen with helm template on 2026-10-19), so both names count.
env_is_true() {
  jq -s -e '[.[] | select((.kind // "Deployment") == "Deployment") | .spec.template.spec.containers[]?.env[]?
             | select((.name == "ENABLE_CONTROLLER_KONNECT" or .name == "KONG_OPERATOR_ENABLE_CONTROLLER_KONNECT") and (.value | tostring) == "true")] | length >= 1' >/dev/null
}

helm template kong-operator kong-operator --repo "$CHART_REPO" --version "$chart_version" \
  --namespace "$OPERATOR_NS" -f "$here/../helm/operator.values.yaml" >"$tmp/rendered.yaml" ||
  { _err "helm template failed, nothing installed"; exit 1; }
yq eval-all -o=json -I=0 'select(.kind == "Deployment")' "$tmp/rendered.yaml" >"$tmp/deployments.jsonl" ||
  { _err "cannot read the rendered Deployments, nothing installed"; exit 1; }
env_is_true <"$tmp/deployments.jsonl" ||
  { _err "the rendered Operator Deployment does not set ENABLE_CONTROLLER_KONNECT=true. Check the value names in helm/operator.values.yaml. Nothing installed"; exit 1; }
jq -s -e '[.[] | .spec.template.spec.containers[]?.image | select(test("kong-operator"))]
          | length >= 1 and all(.[]; test(":[0-9]+\\.[0-9]+\\.[0-9]+"))' <"$tmp/deployments.jsonl" >/dev/null ||
  { _err "the rendered Operator image has no full version tag (for example 2.3.3). Nothing installed"; exit 1; }

helm upgrade --install kong-operator kong-operator --repo "$CHART_REPO" --version "$chart_version" \
  --namespace "$OPERATOR_NS" --create-namespace -f "$here/../helm/operator.values.yaml" --wait --timeout 5m --kube-context "$cur"

kubectl get deployment -n "$OPERATOR_NS" -o json | jq -c '.items[]' | env_is_true ||
  { _err "the live Operator Deployment does not set ENABLE_CONTROLLER_KONNECT=true"; exit 1; }

wait_pods "$OPERATOR_NS" ""
echo "kong operator $chart_version installed in $cur"
