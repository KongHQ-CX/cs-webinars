#!/usr/bin/env bash
# Fill a token Secret from an environment variable. This is the path for
# attendees, who have no Terraform. The value goes to kubectl on stdin only.
# Put the token in the variable without typing it on a command line:
#   read -rs ZONE_TOKEN; export ZONE_TOKEN; fill-from-env.sh zone
#   read -rs OPERATOR_TOKEN; export OPERATOR_TOKEN; fill-from-env.sh operator
# The script turns shell tracing off before it touches the token, so bash -x
# and SHELLOPTS=xtrace do not print it.
set -euo pipefail
# Tracing off first: require_vars and printf below handle the token.
{ set +x; } 2>/dev/null
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

kind="${1:-}"
case "$kind" in
  zone)
    require_vars ZONE_TOKEN
    { set +x; } 2>/dev/null
    printf '%s' "$ZONE_TOKEN" | fill_secret "$ZONE_SECRET_NAMESPACE" "$ZONE_SECRET_NAME" "$SECRET_KEY"
    ;;
  operator)
    require_vars OPERATOR_TOKEN
    { set +x; } 2>/dev/null
    printf '%s' "$OPERATOR_TOKEN" | fill_secret "$OPERATOR_SECRET_NAMESPACE" "$OPERATOR_SECRET_NAME" "$SECRET_KEY" "${OPERATOR_SECRET_LABELS[@]}"
    ;;
  *)
    echo "usage: fill-from-env.sh <zone|operator>" >&2
    exit 2
    ;;
esac
echo "secret filled from the environment: $kind"
