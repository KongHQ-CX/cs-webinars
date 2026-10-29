#!/usr/bin/env bash
# Stage 07: bring back the demo pods that 10-kill-local.sh removed, on the active context, and wait
# until they are Ready. Safe to run when nothing was killed: a Deployment with pods is left alone.
# Env: DEMO_REPLICAS (default 2, the stage 02 replica count), DEMO_NAMESPACE (default demo).
#
# Prerequisites: none beyond a reachable cluster. Safe on any ready-* context.
set -euo pipefail

ns="${DEMO_NAMESPACE:-demo}"
want="${DEMO_REPLICAS:-2}"
[[ "$want" =~ ^[1-9][0-9]*$ ]] || { echo "DEMO_REPLICAS must be a positive integer" >&2; exit 2; }

kubectl get deployment demo-app -n "$ns" -o name >/dev/null 2>&1 || { echo "no demo-app Deployment in $ns, nothing to restore"; exit 0; }
have="$(kubectl get deployment demo-app -n "$ns" -o jsonpath='{.spec.replicas}')"
if [ "$have" = "0" ]; then
  kubectl scale deployment/demo-app -n "$ns" --replicas="$want"
fi
kubectl rollout status deployment/demo-app -n "$ns" --timeout=180s
echo "demo-app restored on $(kubectl config current-context)"
