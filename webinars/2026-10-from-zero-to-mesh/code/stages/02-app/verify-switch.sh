#!/usr/bin/env bash
# Acceptance check for the failure switch.
#
#   verify-switch.sh                    full check across both zones (CTX_1 and CTX_2)
#   verify-switch.sh <percent> [ctx]    read check: every demo pod in ctx reads <percent>
#
# Full check: sets 50 in both contexts, port-forwards to EACH demo pod (not the Service, so a
# request cannot hide on a pod that kept the old value), sends 100 requests per pod, asserts the 503
# share is 40 to 60 percent overall and above 0 on every pod, then sets 0 and asserts no 503.
# Any status other than 200 or 503 fails the check.
#
# ctx for the read check defaults to the active kubectl context.
#
# Prerequisites: stage 02 apply.sh ran in both zones. The full check changes the switch and leaves it at 0.
# Env: CTX_1 (default ready-1), CTX_2 (default ready-2), DEMO_NAMESPACE (default demo),
#      DEMO_LABEL (default app=demo-app), DEMO_CONTAINER (default demo-app).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
setter="$here/../../bin/set-failure.sh"
ns="${DEMO_NAMESPACE:-demo}"
label="${DEMO_LABEL:-app=demo-app}"
container="${DEMO_CONTAINER:-demo-app}"

if [ "$#" -gt 2 ]; then
  echo "usage: verify-switch.sh [percent [context]]" >&2
  exit 2
fi

if [ "$#" -ge 1 ]; then
  want="$1"
  [[ "$want" =~ ^(0|[1-9][0-9]?|100)$ ]] || { echo "percent must be an integer from 0 to 100, got: $want" >&2; exit 2; }
  ctx="${2:-$(kubectl config current-context)}"
  pods="$(kubectl --context "$ctx" -n "$ns" get pods -l "$label" -o name)"
  [ -n "$pods" ] || { echo "no demo pods in namespace $ns on context $ctx" >&2; exit 1; }
  bad=0
  while IFS= read -r pod; do
    [ -n "$pod" ] || continue
    got="$(kubectl --context "$ctx" -n "$ns" exec "${pod#pod/}" -c "$container" -- python3 -I /app/adminctl.py get)" || got="exec failed"
    if [ "$got" != "$want" ]; then
      echo "FAIL [$ctx] ${pod#pod/}: wanted $want, read $got" >&2
      bad=$((bad + 1))
    fi
  done <<<"$pods"
  [ "$bad" -eq 0 ] || exit 1
  echo "failure switch reads $want on every demo pod in $ctx"
  exit 0
fi

ctx1="${CTX_1:-ready-1}"
ctx2="${CTX_2:-ready-2}"
pf_pids=()
cleanup() {
  for p in "${pf_pids[@]:-}"; do kill "$p" 2>/dev/null || true; done
  # Leave the switch off even if an assertion failed.
  KUBECTL_CONTEXT="$ctx1" "$setter" 0 >/dev/null 2>&1 || true
  KUBECTL_CONTEXT="$ctx2" "$setter" 0 >/dev/null 2>&1 || true
}
trap cleanup EXIT

# forward <context> <pod> <local-port>: port-forward to one pod's service port (8080).
forward() {
  kubectl --context "$1" -n "$ns" port-forward "pod/$2" "$3:8080" >/dev/null 2>&1 &
  pf_pids+=("$!")
  for _ in $(seq 1 50); do
    curl -s -m 5 -o /dev/null "http://127.0.0.1:$3/healthz" && return 0
    sleep 0.2
  done
  echo "port-forward to $2 in $1 failed" >&2
  return 1
}

# count_503 <port> <requests>: prints the 503 count. A status other than 200 or 503 fails the check.
count_503() {
  local n=0 i code
  for i in $(seq 1 "$2"); do
    code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$1/")" || code="000"
    case "$code" in
      503) n=$((n + 1)) ;;
      200) ;;
      *) echo "FAIL: unexpected status $code from port $1" >&2; return 1 ;;
    esac
  done
  echo "$n"
}

ports=()   # local ports, one per pod
names=()   # "<context>/<pod>" labels, same order
next_port=18100
for ctx in "$ctx1" "$ctx2"; do
  pods="$(kubectl --context "$ctx" -n "$ns" get pods -l "$label" -o name)"
  [ -n "$pods" ] || { echo "no demo pods on $ctx" >&2; exit 1; }
  while IFS= read -r pod; do
    [ -n "$pod" ] || continue
    forward "$ctx" "${pod#pod/}" "$next_port"
    ports+=("$next_port")
    names+=("$ctx/${pod#pod/}")
    next_port=$((next_port + 1))
  done <<<"$pods"
done

per_pod=100
KUBECTL_CONTEXT="$ctx1" "$setter" 50
KUBECTL_CONTEXT="$ctx2" "$setter" 50
total=0
for i in "${!ports[@]}"; do
  c="$(count_503 "${ports[$i]}" "$per_pod")"
  echo "503 count: ${names[$i]} = $c of $per_pod"
  [ "$c" -gt 0 ] || { echo "FAIL: no 503 on ${names[$i]}" >&2; exit 1; }
  total=$((total + c))
done
sent=$((per_pod * ${#ports[@]}))
echo "overall = $total of $sent"
if [ "$((total * 100))" -lt "$((sent * 40))" ] || [ "$((total * 100))" -gt "$((sent * 60))" ]; then
  echo "FAIL: overall 503 share $total of $sent is outside 40 to 60 percent" >&2
  exit 1
fi

KUBECTL_CONTEXT="$ctx1" "$setter" 0
KUBECTL_CONTEXT="$ctx2" "$setter" 0
for i in "${!ports[@]}"; do
  z="$(count_503 "${ports[$i]}" 50)"
  [ "$z" -eq 0 ] || { echo "FAIL: $z 503 on ${names[$i]} with the switch at 0" >&2; exit 1; }
done
echo "verify-switch OK"
