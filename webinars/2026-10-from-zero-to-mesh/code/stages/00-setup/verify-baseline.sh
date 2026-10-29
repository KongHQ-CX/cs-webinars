#!/usr/bin/env bash
# State before the baseline step. Run after cleanup.sh, at the start of the dry
# run and in the day-of rebuild.
# Both zones: nothing from stage 04 on, failure switch reads 0 on every demo
# pod, every demo pod has its sidecar and is Ready (killed pods are back).
# ready-1 only (zone 2 has no gateway): the stage 03 route and gateway objects
# match their files, gateway pods have the sidecar, every LoadBalancer
# Service has externalTrafficPolicy Local (with EDGE_CONTROL_ACK=1; without it no
# Service may be a LoadBalancer or NodePort), and no NetworkPolicy of ours in the
# gateway namespace admits the world (the Operator's own policy is skipped).
# Who can reach the gateway is the load balancer firewall, not checked here.
# VERIFY_SWITCH overrides the path of the failure switch check.
#
# Prerequisites: cleanup.sh ran on both ready contexts.
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"
# shellcheck source=../../lib/gateway.sh
. "$WEBINAR_CODE_DIR/lib/gateway.sh"

stages_dir="${STAGES_DIR:-$WEBINAR_CODE_DIR/stages}"
demo_ns="${DEMO_NAMESPACE:-demo}"
gateway_ns="kong"
verify_switch="${VERIFY_SWITCH:-$WEBINAR_CODE_DIR/stages/02-app/verify-switch.sh}"
fail=0
bad() { echo "FAIL [$ctx]: $*" >&2; fail=1; }

for ctx in ready-1 ready-2; do
  kc=(kubectl --context "$ctx")

  # 1. No resource from stage 04 onward (the kept stage 03 files are checked in step 4).
  while IFS= read -r file; do
    nn="$(basename "$(dirname "$file")")"
    nn="${nn%%-*}"
    [[ $nn =~ ^[0-9]{2}$ ]] && ((10#$nn >= 4)) || continue
    is_kept_stage_file "$file" && continue
    left="$("${kc[@]}" get -f "$file" --ignore-not-found -o name)"
    [ -z "$left" ] || bad "left over from $(basename "$file"): $left"
  done < <(find "$stages_dir" -mindepth 2 -maxdepth 2 -name '*.yaml' | sort)

  # 2. Failure switch reads 0 on every demo pod of this context.
  if [ -x "$verify_switch" ]; then
    "$verify_switch" 0 "$ctx" || bad "failure switch is not 0 on every demo pod"
  else
    bad "verify-switch.sh missing: $verify_switch"
  fi

  # 3. Sidecar on every demo pod, and every pod Ready (killed pods restored).
  has_sidecar "$demo_ns" "$ctx" || bad "a pod in $demo_ns has no kuma-sidecar"
  notready="$("${kc[@]}" get pods -n "$demo_ns" -o json |
    jq -r '[.items[] | select(([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length) == 0) | .metadata.name] | join(" ")')"
  [ -z "$notready" ] || bad "demo pods not Ready: $notready"

  # 4. Gateway checks, zone 1 only (zone 2 has no gateway).
  if [ "$ctx" = "ready-1" ]; then
    # 4a. Route and gateway back to the stage 03 shape.
    for kept in "${STAGE_KEPT_FILES[@]}"; do
      if [ -f "$stages_dir/$kept" ]; then
        "${kc[@]}" diff -f "$stages_dir/$kept" >/dev/null || bad "$kept differs from the stage 03 shape"
      fi
    done

    # 4b. Gateway pods have the sidecar.
    has_sidecar "$gateway_ns" "$ctx" || bad "a gateway pod has no kuma-sidecar"

    # 4c. Read through this context: every LoadBalancer Service keeps the client address
    # (externalTrafficPolicy Local), and no policy of ours admits the world.
    if [ "${EDGE_CONTROL_ACK:-}" = "1" ]; then
      (
        kubectl() { command kubectl --context "$ctx" "$@"; }
        gateway_svc_local "$gateway_ns"
      ) || bad "a LoadBalancer Service in $gateway_ns does not have externalTrafficPolicy $GATEWAY_TRAFFIC_POLICY (or none exists)"
    else
      (
        kubectl() { command kubectl --context "$ctx" "$@"; }
        gateway_svc_internal "$gateway_ns"
      ) || bad "a LoadBalancer or NodePort Service exists in $gateway_ns but EDGE_CONTROL_ACK is not 1"
    fi
    (
      kubectl() { command kubectl --context "$ctx" "$@"; }
      gateway_no_world_policy "$gateway_ns"
    ) || bad "a NetworkPolicy in $gateway_ns that is not the Operator's admits every source"
  fi
done

[ "$fail" -eq 0 ] && echo "baseline state: ok on ready-1 and ready-2"
exit "$fail"
