#!/usr/bin/env bash
# Shared helpers for the webinar scripts. Source this file, do not run it.
# It sets no shell options, so each caller keeps its own `set -euo pipefail`.
# Validators return non-zero with a one-line message on stderr.

WEBINAR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBINAR_CODE_DIR="$(cd "$WEBINAR_LIB_DIR/.." && pwd)"
export WEBINAR_CODE_DIR
WEBINAR_PLACEHOLDER='__REPLACE_ME__'

# Secret names shared by every script that fills a token Secret. Override with
# the environment if the stage files use other names.
ZONE_SECRET_NAMESPACE="${ZONE_SECRET_NAMESPACE:-kong-mesh-system}"
ZONE_SECRET_NAME="${ZONE_SECRET_NAME:-cp-token}"
OPERATOR_SECRET_NAMESPACE="${OPERATOR_SECRET_NAMESPACE:-kong}"
OPERATOR_SECRET_NAME="${OPERATOR_SECRET_NAME:-konnect-api-auth}"
SECRET_KEY="${SECRET_KEY:-token}"
# The Kong Operator reads only Secrets that carry these labels
# (https://developer.konghq.com/operator/get-started/konnect-crds/authentication/).
# shellcheck disable=SC2034  # read by the scripts that source this file
OPERATOR_SECRET_LABELS=(konghq.com/credential=konnect konghq.com/secret=true)

# Files cleanup.sh keeps and verify-baseline.sh checks against the cluster, as
# <stage directory>/<file name>. Matched by exact name, never by a substring.
STAGE_KEPT_FILES=(03-gateway/40-gateway.yaml 03-gateway/50-httproute.yaml)

# is_kept_stage_file <path>: true when the last directory and the file name match STAGE_KEPT_FILES.
is_kept_stage_file() {
  local path="${1:?path}" key kept
  key="$(basename "$(dirname "$path")")/$(basename "$path")"
  for kept in "${STAGE_KEPT_FILES[@]}"; do
    [ "$key" = "$kept" ] && return 0
  done
  return 1
}

_err() { printf 'error: %s\n' "$*" >&2; }

# require_vars NAME...
# Fails with one line per variable that is unset, empty or still __REPLACE_ME__.
require_vars() {
  local name value bad=0
  for name in "$@"; do
    value="${!name:-}"
    if [ -z "$value" ]; then
      _err "required variable not set: $name"
      bad=1
    elif [ "$value" = "$WEBINAR_PLACEHOLDER" ]; then
      _err "required variable still holds the placeholder $WEBINAR_PLACEHOLDER: $name"
      bad=1
    fi
  done
  return "$bad"
}

# require_ctx <install|ready>: the active kubectl context must start with "<set>-".
require_ctx() {
  local want="${1:-}" cur
  case "$want" in
    install | ready) ;;
    *) _err "require_ctx needs install or ready"; return 1 ;;
  esac
  cur="$(kubectl config current-context 2>/dev/null)" || { _err "cannot read the active kubectl context"; return 1; }
  case "$cur" in
    "$want"-*) return 0 ;;
    *) _err "active context is '$cur', expected one that starts with '$want-'"; return 1 ;;
  esac
}

# pin_kubeconfig <context> [--all]
# Copy the kubeconfig to a private file (mode 600), set its current context to <context>, and
# point KUBECONFIG at it. Another terminal that switches context in the shared kubeconfig then
# cannot redirect this script. The copy holds only <context> (one cluster, one credential), unless
# --all is given for a script that reaches several contexts. The file path is in
# PINNED_KUBECONFIG; the caller removes it in its EXIT trap.
pin_kubeconfig() {
  local ctx="${1:?context}"
  PINNED_KUBECONFIG="$(umask 077 && mktemp "${TMPDIR:-/tmp}/smw-kubeconfig.XXXXXX")" || return 1
  if [ "${2:-}" = "--all" ]; then
    kubectl config view --raw --flatten >"$PINNED_KUBECONFIG" || { _err "cannot copy the kubeconfig"; return 1; }
  else
    kubectl config view --raw --flatten --minify --context="$ctx" >"$PINNED_KUBECONFIG" || { _err "cannot copy the kubeconfig for $ctx"; return 1; }
  fi
  KUBECONFIG="$PINNED_KUBECONFIG" kubectl config use-context "$ctx" >/dev/null || { _err "cannot pin the kubeconfig to $ctx"; return 1; }
  export KUBECONFIG="$PINNED_KUBECONFIG"
}

# require_ctx_1: the active kubectl context must be CTX_1 (default ready-1), the zone with the gateway.
# Every stage script that talks to the gateway starts with this one guard.
require_ctx_1() {
  local want="${CTX_1:-ready-1}" cur
  cur="$(kubectl config current-context 2>/dev/null)" || { _err "cannot read the active kubectl context"; return 1; }
  [ "$cur" = "$want" ] || { _err "this stage runs on $want (the gateway is there), active context is '$cur'"; return 1; }
}

# wait_pods <ns> <selector>: wait until the pods are Ready. An empty selector means all pods.
wait_pods() {
  local ns="${1:?namespace}" sel="${2:-}" names
  local -a get=(kubectl get pods -n "$ns" -o json)
  [ -n "$sel" ] && get+=(-l "$sel")
  # Pods that finished (phase Succeeded, for example a completed Job) never become Ready.
  names="$("${get[@]}" | jq -r '.items[] | select(.status.phase != "Succeeded" and .metadata.deletionTimestamp == null) | "pod/" + .metadata.name')" || return 1
  if [ -z "$names" ]; then
    return 0
  fi
  local -a pods=()
  local p
  while IFS= read -r p; do pods+=("$p"); done <<<"$names"
  kubectl wait --for=condition=Ready "${pods[@]}" -n "$ns" --timeout="${WAIT_TIMEOUT:-180s}"
}

# identity_cutoff <mesh> [context]: the newest creation time among the MeshIdentity and MeshTrust
# objects of the mesh, as an ISO 8601 UTC string (these sort as text). Empty when there are none.
# Setup restarts and the setup check both use it: a pod older than this has no certificate from them.
identity_cutoff() {
  local mesh="${1:?mesh}" ctx="${2:-}"
  local -a kc=(kubectl)
  [ -n "$ctx" ] && kc+=(--context "$ctx")
  "${kc[@]}" get meshidentities,meshtrust -n "$ZONE_SECRET_NAMESPACE" -l "kuma.io/mesh=$mesh" -o json |
    jq -r '[.items[].metadata.creationTimestamp] | max // empty'
}

# old_pods <ns> <selector> <cutoff> [context]: names of Running or Pending pods created before the
# cutoff. Finished pods (Succeeded, Failed) are ignored.
old_pods() {
  local ns="${1:?namespace}" sel="${2:?selector}" cutoff="${3:?cutoff}" ctx="${4:-}"
  local -a kc=(kubectl)
  [ -n "$ctx" ] && kc+=(--context "$ctx")
  "${kc[@]}" get pods -n "$ns" -l "$sel" -o json |
    jq -r --arg t "$cutoff" '[.items[] | select(.status.phase == "Running" or .status.phase == "Pending") | select(.metadata.creationTimestamp < $t) | .metadata.name] | join(" ")'
}

# has_sidecar <ns> [context]: true when the namespace has pods and every pod runs a kuma-sidecar
# container, as a regular container or as an init container.
has_sidecar() {
  local ns="${1:?namespace}" ctx="${2:-}"
  local -a kc=(kubectl)
  [ -n "$ctx" ] && kc+=(--context "$ctx")
  "${kc[@]}" get pods -n "$ns" -o json |
    jq -e '(.items | length) > 0 and all(.items[]; any((.spec.containers[]?, .spec.initContainers[]?); .name == "kuma-sidecar"))' >/dev/null
}

# _is_ipv4 <value>: dotted quad, each part 0 to 255, no leading zeros.
_is_ipv4() {
  local ip="${1:-}" part
  local -a parts
  [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS=. read -r -a parts <<<"$ip"
  for part in "${parts[@]}"; do
    [[ $part =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1
    ((part <= 255)) || return 1
  done
}

# require_public_ipv4 <value>: one IPv4 address that is not private, loopback, link-local, shared,
# documentation, benchmarking, multicast or reserved. Use it before publishing an address.
require_public_ipv4() {
  local ip="${1:-}" a b c
  _is_ipv4 "$ip" || { _err "not an IPv4 address: '$ip'"; return 1; }
  IFS=. read -r a b c _ <<<"$ip"
  if [ "$a" = 0 ] || [ "$a" = 10 ] || [ "$a" = 127 ] || [ "$a" -ge 224 ] ||
    { [ "$a" = 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ]; } ||
    { [ "$a" = 192 ] && [ "$b" = 168 ]; } ||
    { [ "$a" = 169 ] && [ "$b" = 254 ]; } ||
    { [ "$a" = 100 ] && [ "$b" -ge 64 ] && [ "$b" -le 127 ]; } ||
    { [ "$a" = 198 ] && { [ "$b" = 18 ] || [ "$b" = 19 ]; }; } ||
    { [ "$a" = 192 ] && [ "$b" = 0 ] && { [ "$c" = 0 ] || [ "$c" = 2 ]; }; } ||
    { [ "$a" = 198 ] && [ "$b" = 51 ] && [ "$c" = 100 ]; } ||
    { [ "$a" = 203 ] && [ "$b" = 0 ] && [ "$c" = 113 ]; }; then
    _err "address $ip is not a public IPv4 address"
    return 1
  fi
}

# _is_cidr32 <value>: one IPv4 address with /32, not 0.0.0.0.
_is_cidr32() {
  local v="${1:-}" ip
  [[ $v == */32 ]] || return 1
  ip="${v%/32}"
  _is_ipv4 "$ip" || return 1
  [ "$ip" != "0.0.0.0" ]
}

# require_single_cidr32 <value>: exactly one IPv4 /32.
require_single_cidr32() {
  _is_cidr32 "${1:-}" || { _err "expected exactly one IPv4 address with /32 (for example 192.0.2.4/32)"; return 1; }
}

# require_ipv4_cidr <value>: one IPv4 network, mask 8 to 30, not 0.0.0.0.
require_ipv4_cidr() {
  local v="${1:-}" ip mask
  [[ $v =~ ^[0-9.]+/[0-9]{1,2}$ ]] || { _err "expected an IPv4 network such as 192.0.2.0/24"; return 1; }
  ip="${v%/*}"
  mask="${v#*/}"
  _is_ipv4 "$ip" && [ "$ip" != "0.0.0.0" ] && [[ $mask =~ ^(0|[1-9][0-9]?)$ ]] && ((mask >= 8 && mask <= 30)) ||
    { _err "expected an IPv4 network such as 192.0.2.0/24 with a mask from 8 to 30"; return 1; }
}

# require_gateway_spiffe_id <value>: spiffe://<trust domain>/ns/kong/sa/<ServiceAccount>, never the default account.
require_gateway_spiffe_id() {
  local v="${1:-}"
  [[ $v =~ ^spiffe://[a-z0-9.-]+/ns/kong/sa/[a-z0-9-]+$ ]] ||
    { _err "SPIFFE ID must look like spiffe://<trust domain>/ns/kong/sa/<ServiceAccount>"; return 1; }
  [ "${v##*/sa/}" != "default" ] || { _err "SPIFFE ID names the default ServiceAccount: give the gateway its own ServiceAccount"; return 1; }
}

# require_cidr32_list <value>: comma-separated list of one or more IPv4 /32 addresses.
require_cidr32_list() {
  local v="${1:-}" item
  local -a items
  if [ -z "$v" ] || [[ $v == ,* ]] || [[ $v == *, ]] || [[ $v == *,,* ]]; then
    _err "expected a comma-separated list of IPv4 /32 addresses"
    return 1
  fi
  IFS=, read -r -a items <<<"$v"
  for item in "${items[@]}"; do
    _is_cidr32 "$item" || { _err "not an IPv4 /32 address: '$item'"; return 1; }
  done
}

# fill_secret <ns> <name> <key> [label=value ...]
# Reads the value from stdin into a variable inside this process, refuses empty
# and "null", creates the namespace only when it is missing, then creates the Secret from
# /dev/stdin. The value is never in argv, never echoed, never in a file.
# Optional label=value arguments label the Secret (kubectl label --local, so the
# value is not read again). The function turns shell tracing off first, so bash -x
# and SHELLOPTS=xtrace never print the value.
fill_secret() {
  if [ "$#" -lt 3 ]; then
    _err "usage: fill_secret <namespace> <name> <key> [label=value ...]"
    return 1
  fi
  (
    { set +x; } 2>/dev/null
    set -euo pipefail
    unset KONNECT_TOKEN
    ns="$1" name="$2" key="$3"
    shift 3
    value="$(cat)"
    if [ -z "$value" ] || [ "$value" = "null" ]; then
      _err "secret value is empty or null, nothing applied"
      exit 1
    fi
    # Create the namespace only when it is missing. Applying a namespace manifest to an existing
    # namespace strips labels other scripts put on it (the mesh injection labels on kong).
    kubectl get namespace "$ns" >/dev/null 2>&1 </dev/null || kubectl create namespace "$ns" >/dev/null </dev/null
    if [ "$#" -gt 0 ]; then
      printf '%s' "$value" |
        kubectl create secret generic "$name" -n "$ns" --from-file="$key=/dev/stdin" --dry-run=client -o yaml |
        kubectl label --local -f - "$@" -o yaml |
        kubectl apply -n "$ns" -f - >/dev/null
    else
      printf '%s' "$value" |
        kubectl create secret generic "$name" -n "$ns" --from-file="$key=/dev/stdin" --dry-run=client -o yaml |
        kubectl apply -n "$ns" -f - >/dev/null
    fi
  )
}
