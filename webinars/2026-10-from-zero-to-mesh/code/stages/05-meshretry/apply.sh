#!/usr/bin/env bash
# Stage 05: apply the MeshRetry policy to the active context (ready-1, where the gateway runs).
#
# Prerequisites: stages 03 and 04 are in place (the gateway answers, the failure switch reads 50) and
# the active context is ready-1.
#
# Env (required): MESH_NAME, lowercase letters, numbers and hyphens.
# Optional: RENDER_ONLY=1 prints the filled manifest and applies nothing (no cluster needed).
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_vars MESH_NAME || exit 2
[[ "$MESH_NAME" =~ ^[a-z0-9-]+$ ]] || { _err "MESH_NAME must be lowercase letters, numbers and hyphens"; exit 2; }

render() { sed -e "s|\${MESH_NAME}|$MESH_NAME|g" "$here/10-meshretry.yaml"; }

if [ "${RENDER_ONLY:-0}" = "1" ]; then
  render
  exit 0
fi

require_ctx_1 || exit 2
render | kubectl apply -f -
echo "stage 05 applied to $(kubectl config current-context)"
