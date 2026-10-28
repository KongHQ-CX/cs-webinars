#!/usr/bin/env bash
# Stage 00 render step: print the gateway allow rule with MESH_NAME and GATEWAY_SPIFFE_ID filled in.
# It applies nothing. Pipe it to kubectl on each ready cluster:
#   stages/00-setup/render-allow-rule.sh | kubectl apply --validate=strict -f -
#
# Env (both required):
#   MESH_NAME          mesh name, lowercase letters, numbers and hyphens.
#   GATEWAY_SPIFFE_ID  spiffe://<trust domain>/ns/kong/sa/<ServiceAccount>. Read it from the gateway
#                      pod's data plane before the first run. The default ServiceAccount is refused:
#                      an allow rule for it would admit every pod that runs as default.
#
# Prerequisites: the gateway pod runs with its own ServiceAccount (stage 03).
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_vars MESH_NAME GATEWAY_SPIFFE_ID || exit 2
[[ "$MESH_NAME" =~ ^[a-z0-9-]+$ ]] || { _err "MESH_NAME must be lowercase letters, numbers and hyphens"; exit 2; }
require_gateway_spiffe_id "$GATEWAY_SPIFFE_ID" || exit 2

sed -e "s|\${MESH_NAME}|$MESH_NAME|g" -e "s|\${GATEWAY_SPIFFE_ID}|$GATEWAY_SPIFFE_ID|g" \
  "$here/10-meshtrafficpermission-allow-gateway.yaml"
