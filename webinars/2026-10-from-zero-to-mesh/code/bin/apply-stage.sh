#!/usr/bin/env bash
# Apply one numbered stage, then verify it.
# Runs stages/NN-*/apply.sh. A stage with no apply.sh runs its first 10-*.sh
# (stage 04 uses 10-failure-on.sh). Then runs verify.sh.
# Usage: apply-stage.sh <NN>
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

nn="${1:-}"
[[ $nn =~ ^[0-9]{2}$ ]] || { echo "usage: apply-stage.sh <NN>   (two digits, for example 03)" >&2; exit 2; }

stages_dir="${STAGES_DIR:-$WEBINAR_CODE_DIR/stages}"

# Pin a private kubeconfig (all contexts, because stages 00, 02, 04 and 07 reach both ready
# clusters) with the current context fixed, so a context switch in another terminal cannot move
# the stage to a different cluster. The file is removed on exit.
trap 'rm -f "${PINNED_KUBECONFIG:-}"' EXIT
cur_ctx="$(kubectl config current-context)" || { _err "cannot read the active kubectl context"; exit 1; }
pin_kubeconfig "$cur_ctx" --all || exit 1
shopt -s nullglob
dirs=("$stages_dir/$nn"-*/)
shopt -u nullglob
[ "${#dirs[@]}" -eq 1 ] || { _err "expected exactly one stages/$nn-* directory, found ${#dirs[@]}"; exit 1; }
dir="${dirs[0]%/}"

if [ -f "$dir/apply.sh" ]; then
  bash "$dir/apply.sh"
else
  shopt -s nullglob
  tens=("$dir"/10-*.sh)
  shopt -u nullglob
  [ "${#tens[@]}" -ge 1 ] || { _err "$dir has no apply.sh and no 10-*.sh"; exit 1; }
  bash "${tens[0]}"
fi

[ -f "$dir/verify.sh" ] || { _err "$dir has no verify.sh"; exit 1; }
bash "$dir/verify.sh"
