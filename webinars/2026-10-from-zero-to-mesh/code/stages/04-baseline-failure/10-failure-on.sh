#!/usr/bin/env bash
# Stage 04: turn the planted failure on, 50 percent of requests answer 503, in both zones.
# The switch is set on every demo pod through kubectl exec, not through the gateway.
# Env: CTX_1 (default ready-1), CTX_2 (default ready-2).
#
# Prerequisites: stage 02 ran in both zones and the failure switch reads 0.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setter="$here/../../bin/set-failure.sh"

for ctx in "${CTX_1:-ready-1}" "${CTX_2:-ready-2}"; do
  KUBECTL_CONTEXT="$ctx" "$setter" 50
done
