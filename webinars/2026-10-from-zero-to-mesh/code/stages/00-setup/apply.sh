#!/usr/bin/env bash
# Stage 00 apply: what identity needs before the stages that send traffic, on both ready clusters.
# A MeshIdentity already exists (it was created before the webinar). This script does not create one.
# Order:
#   1. Check both contexts exist, then check a MeshIdentity exists on each cluster.
#   2. Copy each zone's CA certificate into the other zones (bin/trust-combine.sh).
#   3. Apply the gateway allow rule on each cluster (render-allow-rule.sh).
#   4. Delete any rule labelled lab-allow (a temporary allow-all used while building).
#   5. Restart the demo app and the gateway pods that started before the identity
#      (restart-workloads.sh).
# With identity on, traffic is denied until a rule allows it, so step 3 lets the gateway in.
#
# Env (required): MESH_NAME, GATEWAY_SPIFFE_ID (spiffe://<trust domain>/ns/kong/sa/<ServiceAccount>).
# Optional: CTX_1, CTX_2 (default ready-1, ready-2), ZONE_CONTEXTS (default "$CTX_1 $CTX_2"),
#   COMBINED=1 (one combined MeshTrust, see bin/trust-combine.sh).
#   TRUST_COMBINE and RESTART_WORKLOADS replace the two helper scripts (used by the tests).
#
# Prerequisites: stages 02 and 03 are in place. The gateway ID is read from the gateway pod, which
# exists only after stage 03, so this stage runs after stage 03 and before stage 04. A MeshIdentity
# exists on both clusters.
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
require_vars MESH_NAME GATEWAY_SPIFFE_ID || exit 2
[[ "$MESH_NAME" =~ ^[a-z0-9-]+$ ]] || { _err "MESH_NAME must be lowercase letters, numbers and hyphens"; exit 2; }
require_gateway_spiffe_id "$GATEWAY_SPIFFE_ID" || exit 2

ctx1="${CTX_1:-ready-1}"
ctx2="${CTX_2:-ready-2}"
contexts=("$ctx1" "$ctx2")
trust_combine="${TRUST_COMBINE:-$WEBINAR_CODE_DIR/bin/trust-combine.sh}"
restart_workloads="${RESTART_WORKLOADS:-$here/restart-workloads.sh}"

# Render first: a bad ID stops the run before any cluster changes.
rule="$("$here/render-allow-rule.sh")"

# Both contexts and both MeshIdentity checks come before the first change.
known="$(kubectl config get-contexts -o name)" || { _err "kubectl could not list contexts"; exit 1; }
for c in "${contexts[@]}"; do
  grep -Fxq -- "$c" <<<"$known" || { _err "context $c does not exist in the kubeconfig"; exit 1; }
done
for c in "${contexts[@]}"; do
  if ! found="$(kubectl --context "$c" get meshidentities -n "$ZONE_SECRET_NAMESPACE" -o name)"; then
    _err "kubectl could not list MeshIdentity on $c (see the error above)"
    exit 1
  fi
  [ -n "$found" ] ||
    { _err "no MeshIdentity on $c. Create it through the Konnect Mesh API first (see the README, section Identity)"; exit 1; }
done

ZONE_CONTEXTS="${ZONE_CONTEXTS:-${contexts[*]}}" "$trust_combine"

for c in "${contexts[@]}"; do
  printf '%s\n' "$rule" | kubectl --context "$c" apply --validate=strict -f -
  kubectl --context "$c" delete meshtrafficpermissions -A -l lab-allow=true --ignore-not-found
done

for c in "${contexts[@]}"; do
  KUBECTL_CONTEXT="$c" "$restart_workloads"
done
echo "stage 00 applied to ${contexts[*]}"
