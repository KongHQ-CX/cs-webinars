#!/usr/bin/env bash
# Set the demo app failure percent on every demo pod in the active kubectl context, then read each pod back.
# Run it once per context (ready-1 and ready-2) to cover both zones.
#
#   set-failure.sh <percent>      percent is an integer from 0 to 100
#
# Exit codes: 0 done, 1 an exec failed or a pod reads back another value, 2 bad argument,
# 3 no demo pod found (cleanup.sh treats 3 as a warning while it recovers a killed zone).
# It exits non-zero if the argument is invalid, no pod is found, any exec fails, or any pod reads back a
# different value. It tries every pod before it exits. The admin listener (127.0.0.1:9911) is loopback
# only, so the script goes through kubectl exec.
# Env: KUBECTL_CONTEXT (optional), DEMO_NAMESPACE (default demo), DEMO_LABEL (default app=demo-app), DEMO_CONTAINER (default demo-app).
set -euo pipefail

usage() { echo "usage: set-failure.sh <percent 0..100>" >&2; exit 2; }

[ "$#" -eq 1 ] || usage
percent="$1"
[[ "$percent" =~ ^(0|[1-9][0-9]?|100)$ ]] || { echo "percent must be an integer from 0 to 100, got: $percent" >&2; exit 2; }

ns="${DEMO_NAMESPACE:-demo}"
label="${DEMO_LABEL:-app=demo-app}"
container="${DEMO_CONTAINER:-demo-app}"

# KUBECTL_CONTEXT picks a context without switching the shell's active one.
k=(kubectl)
[ -z "${KUBECTL_CONTEXT:-}" ] || k+=(--context "$KUBECTL_CONTEXT")

ctx="${KUBECTL_CONTEXT:-$(kubectl config current-context)}"
pods="$("${k[@]}" -n "$ns" get pods -l "$label" -o name)"
[ -n "$pods" ] || { echo "no demo pods in namespace $ns on context $ctx" >&2; exit 3; }

bad=0
count=0
while IFS= read -r pod; do
  [ -n "$pod" ] || continue
  count=$((count + 1))
  name="${pod#pod/}"
  # A failed exec marks this pod bad and the loop goes on, so one dead pod does not leave the rest unset.
  if ! "${k[@]}" -n "$ns" exec "$name" -c "$container" -- python3 -I /app/adminctl.py set "$percent" >/dev/null; then
    echo "EXEC FAILED (set) $name" >&2
    bad=$((bad + 1))
    continue
  fi
  if ! got="$("${k[@]}" -n "$ns" exec "$name" -c "$container" -- python3 -I /app/adminctl.py get)"; then
    echo "EXEC FAILED (get) $name" >&2
    bad=$((bad + 1))
    continue
  fi
  if [ "$got" != "$percent" ]; then
    echo "MISMATCH $name: wanted $percent, read $got" >&2
    bad=$((bad + 1))
  fi
done <<< "$pods"

if [ "$bad" -ne 0 ]; then
  echo "failure switch failed or differs on $bad of $count pods in $ctx" >&2
  exit 1
fi
echo "failure switch = $percent on $count pods in $ctx"
