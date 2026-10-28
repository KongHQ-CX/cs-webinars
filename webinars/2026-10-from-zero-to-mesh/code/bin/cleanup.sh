#!/usr/bin/env bash
# Return a ready cluster to the state before the baseline step. Idempotent.
# Removes what stage 04 and later add: failure switch back to 0, MeshRetry,
# the stage 06 client pod. It keeps stage 00 (trust copy, allow
# rule) and stages 02 and 03. It restores the pods stage 07 kills and reverts
# the gateway path stage 07 changes (route backend and the gateway's
# kuma.io/reachable-backends entry). Order: stage 07 restore and revert first,
# then the failure switch reset, because a killed zone has no pod to reset.
# A missing demo pod set at the switch step is a warning, not a stop. A pod that
# reads back another value still fails the run.
# Usage: cleanup.sh          clean the active ready-* context
#        cleanup.sh both     clean ready-1 then ready-2 through a private copy of
#                            the kubeconfig, so your current-context never changes
#
# YAML files in stages 04 and later are deleted, except the files named in
# STAGE_KEPT_FILES (lib/common.sh). Those belong to the stage 03 shape. Stage 07's
# revert script restores the route and gateway it changes.
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

stages_dir="${STAGES_DIR:-$WEBINAR_CODE_DIR/stages}"

clean_one() {
  local dir nn file hook rc
  echo "cleanup on context $(kubectl config current-context)"

  for hook in 20-restore-local.sh 30-revert-gateway-path.sh; do
    if [ -f "$stages_dir/07-multizone-failover/$hook" ]; then
      bash "$stages_dir/07-multizone-failover/$hook"
    fi
  done

  if [ -x "$WEBINAR_CODE_DIR/bin/set-failure.sh" ]; then
    rc=0
    "$WEBINAR_CODE_DIR/bin/set-failure.sh" 0 || rc=$?
    case "$rc" in
      0) ;;
      3) echo "warning: no demo pods found, failure switch reset skipped on $(kubectl config current-context)" >&2 ;;
      *) exit "$rc" ;;
    esac
  fi

  # Stage directories 04 and up, last stage first.
  while IFS= read -r dir; do
    nn="$(basename "$dir")"
    nn="${nn%%-*}"
    [[ $nn =~ ^[0-9]{2}$ ]] || continue
    ((10#$nn >= 4)) || continue
    while IFS= read -r file; do
      is_kept_stage_file "$file" && continue
      kubectl delete -f "$file" --ignore-not-found
    done < <(find "$dir" -maxdepth 1 -name '*.yaml' | sort -r)
  done < <(find "$stages_dir" -maxdepth 1 -mindepth 1 -type d | sort -r)

  # Killed pods come back through their Deployments. Wait for them.
  wait_pods "${DEMO_NAMESPACE:-demo}" ""
}

if [ "${1:-}" = "both" ]; then
  # A private, flattened copy of the kubeconfig (mode 600, removed on exit). The
  # context switch happens in that copy only.
  private="$(umask 077 && mktemp "${TMPDIR:-/tmp}/smw-kubeconfig.XXXXXX")"
  trap 'rm -f "$private"' EXIT
  kubectl config view --raw --flatten >"$private"
  for ctx in ready-1 ready-2; do
    KUBECONFIG="$private" kubectl config use-context "$ctx" >/dev/null
    (
      export KUBECONFIG="$private"
      clean_one
    )
  done
else
  require_ctx ready
  # Pin the run to the context checked above: a private copy of the kubeconfig, so a context switch
  # in another terminal cannot redirect the deletes.
  pinned="$(kubectl config current-context)"
  private="$(umask 077 && mktemp "${TMPDIR:-/tmp}/smw-kubeconfig.XXXXXX")"
  trap 'rm -f "$private"' EXIT
  kubectl config view --raw --flatten >"$private"
  KUBECONFIG="$private" kubectl config use-context "$pinned" >/dev/null
  (
    export KUBECONFIG="$private"
    clean_one
  )
fi
