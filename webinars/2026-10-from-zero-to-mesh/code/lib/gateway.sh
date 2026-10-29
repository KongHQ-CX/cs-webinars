#!/usr/bin/env bash
# Helpers for the stage checks that send requests through the gateway. Source this file, do not run it.
# It needs lib/common.sh sourced first (for _err). It sets no shell options.

# gateway_url: prints http://<address> for the gateway on the active context.
# GATEWAY_URL wins when set. Otherwise the address is read from the gateway's ingress Service in
# namespace kong.
gateway_url() {
  local ns="kong" ip
  if [ -n "${GATEWAY_URL:-}" ]; then
    printf '%s' "${GATEWAY_URL%/}"
    return 0
  fi
  ip="$(kubectl get svc -n "$ns" -l gateway-operator.konghq.com/dataplane-service-type=ingress \
    -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null)" || ip=""
  [ -n "$ip" ] || { _err "no gateway address: set GATEWAY_URL or wait for the LoadBalancer in namespace $ns"; return 1; }
  printf 'http://%s' "$ip"
}

# request_once <url>: prints "<http status> <service> <zone>" for one GET. A field is "-" when the
# body has none. Status 000 means no response.
request_once() {
  local url="${1:?url}" out code body fields
  out="$(curl -s -m 5 -w '\n%{http_code}' "$url/" 2>/dev/null)" || out=$'\n000'
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  fields="$(printf '%s' "$body" | jq -r '"\(.service // "-") \(.zone // "-")"' 2>/dev/null)" || fields=""
  [ -n "$fields" ] || fields="- -"
  printf '%s %s\n' "$code" "$fields"
}

# count_requests <url> <n>: sends n GETs and prints "<200 count> <503 count> <other count>".
count_requests() {
  local url="${1:?url}" n="${2:?count}" line ok=0 fail=0 other=0
  for _ in $(seq 1 "$n"); do
    line="$(request_once "$url")"
    case "${line%% *}" in
      200) ok=$((ok + 1)) ;;
      503) fail=$((fail + 1)) ;;
      *) other=$((other + 1)) ;;
    esac
  done
  printf '%s %s %s\n' "$ok" "$fail" "$other"
}

# The GatewayConfiguration has no source range field (Operator v2.3.3), and a NetworkPolicy cannot
# narrow the gateway: the Operator creates its own policy for the gateway pods whose proxy and metrics
# rules have no from list, policies add up, and the Operator reverts edits to its own. The edge control
# is the firewall rule pair on the load balancer. The helpers below check what the cluster can show.

# The traffic policy that keeps the client address for the load balancer firewall. Four gates use it: 20-gatewayconfiguration.yaml, the manifest checker, the apply.sh
# read-backs and gateway_svc_local below (also used by verify.sh and verify-baseline.sh). If the lab
# shows Local is not needed, relax those four together.
GATEWAY_TRAFFIC_POLICY="Local"

# gateway_svc_local <ns>: true when the namespace has at least one LoadBalancer Service and every
# one has externalTrafficPolicy $GATEWAY_TRAFFIC_POLICY. A Service without the field (Cluster by
# default) fails.
gateway_svc_local() {
  local ns="${1:?namespace}"
  kubectl get svc -n "$ns" -o json |
    jq -e --arg want "$GATEWAY_TRAFFIC_POLICY" '[.items[] | select(.spec.type == "LoadBalancer")] as $lb
      | ($lb | length) > 0 and all($lb[]; .spec.externalTrafficPolicy == $want)' >/dev/null
}

# gateway_svc_internal <ns>: true when no Service in the namespace is a LoadBalancer or a NodePort,
# so nothing is exposed outside the cluster. (The stage keeps the ingress Service a ClusterIP until
# EDGE_CONTROL_ACK=1 says the load balancer firewall is in place.)
gateway_svc_internal() {
  local ns="${1:?namespace}"
  kubectl get svc -n "$ns" -o json |
    jq -e '[.items[] | select(.spec.type == "LoadBalancer" or .spec.type == "NodePort")] | length == 0' >/dev/null
}

# gateway_no_world_policy <ns>: true when no NetworkPolicy of ours in the namespace admits the world:
# an ipBlock of 0.0.0.0/0 or ::/0, an empty namespaceSelector, an empty peer, an empty rule, or a rule
# with ports and no from list. A policy is skipped only when the Operator owns it (an ownerReference of
# kind Gateway or DataPlane) or its name starts with demo-gateway-limit-admin-api-: that policy is open
# on the proxy and metrics ports by design.
gateway_no_world_policy() {
  local ns="${1:?namespace}"
  kubectl get networkpolicy -n "$ns" -o json |
    jq -e '[.items[]
        | select(((.metadata.ownerReferences // []) | any(.kind == "Gateway" or .kind == "DataPlane")) | not)
        | select((.metadata.name // "") | startswith("demo-gateway-limit-admin-api-") | not)
        | .spec.ingress[]?
        | select(((.from // []) | length) == 0
                 or any(.from[]?;
                        (. == {})
                        or ((.ipBlock.cidr // "") == "0.0.0.0/0")
                        or ((.ipBlock.cidr // "") == "::/0")
                        or (has("namespaceSelector") and .namespaceSelector == {})))]
      | length == 0' >/dev/null
}

# gateway_observed_generation <ns>: sum of status.observedGeneration over the Deployments in the
# namespace. It rises when the Deployment controller has seen a changed pod template.
gateway_observed_generation() {
  local ns="${1:?namespace}"
  kubectl get deployment -n "$ns" -o json | jq '[.items[].status.observedGeneration // 0] | add // 0'
}

# gateway_template_current <ns>: true when every Deployment's pod template carries the same
# kuma.io/reachable-backends value as the Gateway's infrastructure annotation.
gateway_template_current() {
  local ns="${1:?namespace}" want
  want="$(kubectl get gateway demo-gateway -n "$ns" -o json | jq -r '.spec.infrastructure.annotations["kuma.io/reachable-backends"] // ""')"
  kubectl get deployment -n "$ns" -o json |
    jq -e --arg want "$want" '.items | length > 0 and all(.[]; ((.spec.template.metadata.annotations["kuma.io/reachable-backends"] // "") | rtrimstr("\n")) == $want)' >/dev/null
}

# wait_gateway_rollout <ns> <generation-before>
# Call it after applying a Gateway change, with the value gateway_observed_generation gave before the
# apply. A Deployment that is already Available says nothing about a pending change, so this waits for
# a new observedGeneration (or a pod template that already matches the Gateway), then for the rollout.
# Env: ROLLOUT_POLLS (default 60 polls of 2 seconds), ROLLOUT_TIMEOUT (default 180s).
wait_gateway_rollout() {
  local ns="${1:?namespace}" before="${2:?generation before}" now seen=0 d
  for _ in $(seq 1 "${ROLLOUT_POLLS:-60}"); do
    now="$(gateway_observed_generation "$ns")" || now="$before"
    if [ "$now" -gt "$before" ] || gateway_template_current "$ns"; then seen=1; break; fi
    sleep 2
  done
  [ "$seen" -eq 1 ] || { _err "the gateway Deployment did not pick up the change in $((${ROLLOUT_POLLS:-60} * 2)) seconds"; return 1; }
  for d in $(kubectl get deployment -n "$ns" -o name); do
    kubectl rollout status "$d" -n "$ns" --timeout="${ROLLOUT_TIMEOUT:-180s}" || return 1
  done
  wait_pods "$ns" ""
}

# wait_gateway_warm <url> [consecutive=40] [timeout=90]
# Call it before a check that needs every request to answer 200, right after an apply rolled the
# gateway. Observed: for some seconds after the rollout some requests fail, then
# all answer 200. It sends GET <url>/ every 0.5 seconds and returns when it has seen <consecutive>
# answers of 200 in a row (40 is 20 seconds); any other answer resets the count. It fails when the
# <timeout> seconds pass ($SECONDS deadline, plus a cap of 2 polls per second so a fake sleep in tests
# still ends), naming the last status and the count. Prints "gateway warm after Ns" on success.
# Env: WARM_CONSECUTIVE and WARM_TIMEOUT override the defaults; both must be positive integers.
# Do not call it where a failure switch is on and non-200 answers are expected, or where the gateway
# did not just roll (failover and restore beats show the failures on purpose).
wait_gateway_warm() {
  local url="${1:?url}" want="${2:-${WARM_CONSECUTIVE:-40}}" timeout="${3:-${WARM_TIMEOUT:-90}}"
  case "$want" in '' | *[!0-9]* | 0) _err "WARM_CONSECUTIVE must be a positive integer (no unit), got '$want'"; return 2 ;; esac
  case "$timeout" in '' | *[!0-9]* | 0) _err "WARM_TIMEOUT must be a positive integer of seconds (no unit), got '$timeout'"; return 2 ;; esac
  local polls=$((timeout * 2)) start="$SECONDS" streak=0 line code="000"
  for _ in $(seq 1 "$polls"); do
    line="$(request_once "$url")"
    code="${line%% *}"
    if [ "$code" = "200" ]; then streak=$((streak + 1)); else streak=0; fi
    if [ "$streak" -ge "$want" ]; then
      echo "gateway warm after $((SECONDS - start))s"
      return 0
    fi
    [ "$((SECONDS - start))" -lt "$timeout" ] || break
    sleep 0.5
  done
  _err "the gateway did not warm up: $streak of $want consecutive 200 answers after ${timeout} seconds (last status $code)"
  return 1
}
