#!/usr/bin/env bash
# Stage 00 check: setup is present on ready-1 and ready-2.
# Checks: MeshIdentity, the MeshTrust copies that bin/trust-combine.sh applies, the exact-spiffeID
# allow rule, no rule labelled lab-allow, and every demo and gateway pod created after the
# identity (so each pod restarted after identity was on).
# MeshTrust copies: by default one "<zone>-trust" per other zone (not generated, same mesh, a trust
# domain and a CA bundle). With COMBINED=1 one "webinar-combined-trust" instead, the name
# trust-combine.sh gives the combined object.
# Env: MESH_NAME (required), COMBINED (optional, 1 when trust-combine.sh ran with COMBINED=1).
# Nothing here reads a Secret.
#
# Prerequisites: the zones joined, MeshIdentity exists, trust-combine.sh ran, and the allow rule
# was applied (render-allow-rule.sh piped to kubectl apply).
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
require_vars MESH_NAME || exit 2
case "${COMBINED:-}" in "" | 0 | 1) ;; *) _err "COMBINED must be 1 or unset"; exit 2 ;; esac
mesh_ns="${ZONE_SECRET_NAMESPACE}"
demo_ns="${DEMO_NAMESPACE:-demo}"
gateway_ns="kong"
allow_file="$here/10-meshtrafficpermission-allow-gateway.yaml"
combined_name=webinar-combined-trust
fail=0
bad() { echo "FAIL [$ctx]: $*" >&2; fail=1; }

for ctx in "${CTX_1:-ready-1}" "${CTX_2:-ready-2}"; do
  kc=(kubectl --context "$ctx")

  if [ -z "$("${kc[@]}" get meshidentities -n "$mesh_ns" -o name)" ]; then bad "no MeshIdentity in $mesh_ns"; fi
  # The same cutoff restart-workloads.sh uses: the newest MeshIdentity or MeshTrust of this mesh.
  ident="$(identity_cutoff "$MESH_NAME" "$ctx")"

  # The copies trust-combine.sh made: not generated (no origin in spec or status), same mesh.
  copies="$("${kc[@]}" get meshtrust -n "$mesh_ns" -o json | jq -c --arg mesh "$MESH_NAME" '
    [.items[]
      | select(.metadata.labels["kuma.io/mesh"] == $mesh)
      | select(.spec.origin == null and .status.origin == null)
      | select((.spec.trustDomain // "") != "" and ((.spec.caBundles // []) | length) > 0)
      | .metadata.name]')" || copies="[]"
  if [ "${COMBINED:-}" = "1" ]; then
    jq -e --arg n "$combined_name" 'index($n) != null' <<<"$copies" >/dev/null || bad "combined MeshTrust '$combined_name' missing or empty"
  else
    jq -e 'map(select(endswith("-trust"))) | length >= 1' <<<"$copies" >/dev/null || bad "no per-zone MeshTrust copy (<zone>-trust) with a trust domain and a CA bundle: run bin/trust-combine.sh"
  fi

  if [ -f "$allow_file" ]; then
    [ -n "$("${kc[@]}" get -f "$allow_file" --ignore-not-found -o name)" ] || bad "gateway allow rule not applied"
  else
    bad "10-meshtrafficpermission-allow-gateway.yaml missing"
  fi

  lab="$("${kc[@]}" get meshtrafficpermissions -A -l lab-allow=true -o name)"
  [ -z "$lab" ] || bad "lab-allow rule still present: $lab"

  if [ -n "$ident" ]; then
    # Same selectors as restart-workloads.sh. Running or Pending pods only.
    for sel in "$demo_ns|app=demo-app" "$gateway_ns|gateway-operator.konghq.com/managed-by=dataplane"; do
      old="$(old_pods "${sel%%|*}" "${sel#*|}" "$ident" "$ctx")"
      [ -z "$old" ] || bad "pods in ${sel%%|*} older than the identity or trust copy, restart them: $old"
    done
  fi
done

[ "$fail" -eq 0 ] && echo "stage 00 setup: ok on ready-1 and ready-2"
exit "$fail"
