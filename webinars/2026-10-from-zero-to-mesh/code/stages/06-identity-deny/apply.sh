#!/usr/bin/env bash
# Stage 06: add a second caller, the denied client, on the active context (ready-1).
# The MeshIdentity is not applied here: it was in place before the webinar (shown/meshidentity.yaml
# is the read-only copy to show). This script only checks that it exists.
#
# Env (all required): DEMO_IMAGE (ends in @sha256:<64 hex>), MESH_NAME.
# Optional: RENDER_ONLY=1 prints the filled manifest and applies nothing (no cluster needed).
#
# Prerequisites: stage 00 ran (so it ran after stage 03), stages 02 and 03 are in place, and the
# active context is ready-1.
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_vars DEMO_IMAGE MESH_NAME || exit 2
[[ "$DEMO_IMAGE" =~ @sha256:[0-9a-f]{64}$ ]] || { _err "DEMO_IMAGE must end with @sha256: and 64 hex characters"; exit 2; }
[[ "$DEMO_IMAGE" =~ ^[A-Za-z0-9./:_@-]+$ ]] || { _err "DEMO_IMAGE has unexpected characters"; exit 2; }
[[ "$MESH_NAME" =~ ^[a-z0-9-]+$ ]] || { _err "MESH_NAME must be lowercase letters, numbers and hyphens"; exit 2; }

render() {
  sed -e "s|\${DEMO_IMAGE}|$DEMO_IMAGE|g" -e "s|\${MESH_NAME}|$MESH_NAME|g" "$here/20-denied-client.yaml"
}

if [ "${RENDER_ONLY:-0}" = "1" ]; then
  render
  exit 0
fi

require_ctx_1 || exit 2
if ! found="$(kubectl get meshidentities -n "$ZONE_SECRET_NAMESPACE" -o name)"; then
  _err "kubectl could not list MeshIdentity (see the error above)"
  exit 1
fi
[ -n "$found" ] ||
  { _err "no MeshIdentity in $ZONE_SECRET_NAMESPACE. Create it through the Konnect Mesh API first (see the README, section Identity, and shown/meshidentity.yaml)"; exit 1; }

render | kubectl apply --validate=strict -f -
kubectl rollout status deployment/denied-client -n "${DEMO_NAMESPACE:-demo}" --timeout=180s
echo "stage 06 applied to $(kubectl config current-context)"
