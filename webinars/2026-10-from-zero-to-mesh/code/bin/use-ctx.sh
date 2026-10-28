#!/usr/bin/env bash
# Switch kubectl to install-<n> or ready-<n> and write a prompt marker.
# Usage: use-ctx.sh <install|ready> [1|2]   (zone defaults to 1)
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

set_name="${1:-}"
zone="${2:-1}"
case "$set_name" in install | ready) ;; *) echo "usage: use-ctx.sh <install|ready> [1|2]" >&2; exit 2 ;; esac
case "$zone" in 1 | 2) ;; *) echo "usage: use-ctx.sh <install|ready> [1|2]" >&2; exit 2 ;; esac
ctx="$set_name-$zone"

# Capture the list first: with pipefail, grep -q closing the pipe early can make kubectl exit
# non-zero and report a context that exists as missing (seen on ready-1, 2026-10-19).
contexts="$(kubectl config get-contexts -o name)" || { _err "kubectl could not list contexts"; exit 1; }
if ! grep -qx -- "$ctx" <<<"$contexts"; then
  _err "no kubectl context named $ctx"
  exit 1
fi
if command -v kubectx >/dev/null 2>&1; then
  kubectx "$ctx" >/dev/null
else
  kubectl config use-context "$ctx" >/dev/null
fi

# The prompt reads this file (see README). A script cannot change its parent's prompt.
state_dir="${WEBINAR_STATE_DIR:-${XDG_STATE_HOME:-${HOME:?HOME is not set}/.local/state}/service-mesh-webinar}"
mkdir -p "$state_dir"
printf '%s\n' "$ctx" >"$state_dir/context"
echo "active context: $ctx"
