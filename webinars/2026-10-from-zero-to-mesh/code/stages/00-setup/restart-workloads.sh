#!/usr/bin/env bash
# Stage 00: restart the demo app and the gateway when their pods started before the newest
# MeshIdentity or MeshTrust of the mesh, so the pods start with the identity in place.
# Acts on KUBECTL_CONTEXT, or on the active context when it is unset.
#   demo app   Deployments with the label app=demo-app in DEMO_NAMESPACE
#   gateway    Deployments in namespace kong with the label gateway-operator.konghq.com/managed-by=dataplane
# Other workloads are left alone. A second run restarts nothing. A selector that matches no Deployment
# is skipped (zone 2 has no gateway).
# After the rollout the script checks the pod ages again. A Running or Pending pod that is still older
# than the cutoff is deleted by label so its Deployment recreates it. If a pod is still old after that,
# the script stops with an error.
# Env (required): MESH_NAME. Optional: KUBECTL_CONTEXT, DEMO_NAMESPACE (default demo),
# ROLLOUT_TIMEOUT (default 180s).
#
# Prerequisites: the MeshIdentity exists on this context (apply.sh checks it first).
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

require_vars MESH_NAME || exit 2
[[ "$MESH_NAME" =~ ^[a-z0-9-]+$ ]] || { _err "MESH_NAME must be lowercase letters, numbers and hyphens"; exit 2; }
demo_ns="${DEMO_NAMESPACE:-demo}"
[[ "$demo_ns" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { _err "DEMO_NAMESPACE must be a Kubernetes namespace name"; exit 2; }

# KUBECTL_CONTEXT picks a context without switching the shell's active one. The function also
# covers the kubectl calls made by the helpers in lib/common.sh.
if [ -n "${KUBECTL_CONTEXT:-}" ]; then
  [[ $KUBECTL_CONTEXT =~ ^[A-Za-z0-9._:/@-]+$ ]] || { _err "unexpected characters in KUBECTL_CONTEXT"; exit 2; }
  kubectl() { command kubectl --context "$KUBECTL_CONTEXT" "$@"; }
fi
timeout="${ROLLOUT_TIMEOUT:-180s}"

cutoff="$(identity_cutoff "$MESH_NAME")"
[ -n "$cutoff" ] || { _err "no MeshIdentity or MeshTrust for mesh $MESH_NAME in $ZONE_SECRET_NAMESPACE: nothing to restart for"; exit 1; }

# restart_workloads <ns> <label selector>
restart_workloads() {
  local ns="$1" sel="$2" old deployments d
  old="$(old_pods "$ns" "$sel" "$cutoff")"
  if [ -z "$old" ]; then
    echo "$ns ($sel): every pod started after the identity, nothing to restart"
    return 0
  fi
  deployments="$(kubectl get deployment -n "$ns" -l "$sel" -o name)"
  if [ -z "$deployments" ]; then
    echo "$ns ($sel): no Deployment, skipped"
    return 0
  fi
  for d in $deployments; do
    kubectl rollout restart "deployment/${d##*/}" -n "$ns"
  done
  for d in $deployments; do
    kubectl rollout status "deployment/${d##*/}" -n "$ns" --timeout="$timeout"
  done
  old="$(old_pods "$ns" "$sel" "$cutoff")"
  if [ -n "$old" ]; then
    echo "$ns ($sel): pods older than the identity remain after the rollout ($old), deleting them by label" >&2
    kubectl delete pod -n "$ns" -l "$sel"
    for d in $deployments; do
      kubectl rollout status "deployment/${d##*/}" -n "$ns" --timeout="$timeout"
    done
    old="$(old_pods "$ns" "$sel" "$cutoff")"
    [ -z "$old" ] || { _err "$ns ($sel): pods still older than the identity: $old"; return 1; }
  fi
  echo "$ns ($sel): restarted $(wc -w <<<"$deployments" | tr -d ' ') Deployment(s)"
}

restart_workloads "$demo_ns" app=demo-app
restart_workloads kong gateway-operator.konghq.com/managed-by=dataplane
