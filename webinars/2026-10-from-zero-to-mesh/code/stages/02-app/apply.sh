#!/usr/bin/env bash
# Stage 02: apply the demo app to the active kubectl context (run once per ready cluster).
#
# Env (all required):
#   DEMO_IMAGE   image reference ending in @sha256:<64 hex digits>. Never committed.
#   ZONE_NAME    zone name this cluster reports, for example the zone control plane's zone name.
#   MESH_NAME    mesh name, lowercase letters, digits and hyphens.
# Optional: RENDER_ONLY=1 prints the filled manifests and applies nothing (no cluster needed).
#
# Prerequisites: the zone control plane runs in this cluster and the active context is a ready
# context. Run it once per ready cluster, with that cluster's ZONE_NAME.
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "$0")" && pwd)/../../lib/common.sh"

here="$(cd "$(dirname "$0")" && pwd)"

require_vars DEMO_IMAGE ZONE_NAME MESH_NAME || exit 2
[[ "$DEMO_IMAGE" =~ @sha256:[0-9a-f]{64}$ ]] || { echo "DEMO_IMAGE must end with @sha256: and 64 hex digits" >&2; exit 2; }
[[ "$DEMO_IMAGE" != *__REPLACE_ME__* ]] || { echo "DEMO_IMAGE is still the placeholder" >&2; exit 2; }
[[ "$ZONE_NAME" =~ ^[a-z0-9-]+$ ]] || { echo "ZONE_NAME must be lowercase letters, digits and hyphens" >&2; exit 2; }
[[ "$MESH_NAME" =~ ^[a-z0-9-]+$ ]] || { echo "MESH_NAME must be lowercase letters, digits and hyphens" >&2; exit 2; }
[[ "$DEMO_IMAGE" =~ ^[A-Za-z0-9./:_@-]+$ ]] || { echo "DEMO_IMAGE has unexpected characters" >&2; exit 2; }

render() { # files to fill, default all
  local f files=("$@")
  [ "${#files[@]}" -gt 0 ] || files=("$here"/[0-9][0-9]-*.yaml)
  for f in "${files[@]}"; do
    echo "---"
    sed -e "s|\${DEMO_IMAGE}|$DEMO_IMAGE|g" -e "s|\${ZONE_NAME}|$ZONE_NAME|g" -e "s|\${MESH_NAME}|$MESH_NAME|g" "$f"
  done
}

if [ "${RENDER_ONLY:-0}" = "1" ]; then
  render
  exit 0
fi

require_ctx ready || exit 2
ctx="$(kubectl config current-context)"

# Namespace first so the sidecar label exists before any pod starts.
render "$here/10-namespace.yaml" | kubectl apply -f -
render | kubectl apply -f -
kubectl -n demo rollout status deployment/demo-app --timeout=180s
echo "stage 02 applied to $ctx"
