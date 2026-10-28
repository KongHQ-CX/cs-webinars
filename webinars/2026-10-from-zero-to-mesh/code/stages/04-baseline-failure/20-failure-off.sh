#!/usr/bin/env bash
# Stage 04: turn the planted failure off in both zones.
# Env: CTX_1 (default ready-1), CTX_2 (default ready-2).
#
# Prerequisites: stage 02 ran in both zones.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setter="$here/../../bin/set-failure.sh"

for ctx in "${CTX_1:-ready-1}" "${CTX_2:-ready-2}"; do
  KUBECTL_CONTEXT="$ctx" "$setter" 0
done
