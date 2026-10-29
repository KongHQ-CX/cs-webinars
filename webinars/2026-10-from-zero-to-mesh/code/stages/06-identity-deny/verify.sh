#!/usr/bin/env bash
# Stage 06 check on ready-1:
#   1. The client pod runs the sidecar, and 10 requests from it to the demo app all get 403. A 2xx,
#      a 503 (the failure switch may be on) and a 000 (no sidecar, no DNS) each fail the check.
#   2. The same client gets a refused connection (000) on the demo app's admin port.
#   3. Every MeshTrafficPermission, whatever its labels: none uses spec.from, every allow entry names
#      one caller as spiffe://<trust domain>/ns/<name>/sa/<name>, and at least one allow entry exists.
#   4. The gateway path still works: 10 requests, at least one answers 200, and none is denied
#      (a 503 from the failure switch is not a deny).
# Env: GATEWAY_URL (default: the gateway Service address), DEMO_APP_URL (default
#   http://demo-app.demo.svc.cluster.local/), DEMO_NAMESPACE (default demo).
#
# Prerequisites: stage 06 apply.sh ran, stage 00 ran, the active context is ready-1 (CTX_1).
set -euo pipefail
# shellcheck source=../../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"
# shellcheck source=../../lib/gateway.sh
. "$WEBINAR_CODE_DIR/lib/gateway.sh"

require_ctx_1 || exit 1
ns="${DEMO_NAMESPACE:-demo}"
app_url="${DEMO_APP_URL:-http://demo-app.demo.svc.cluster.local/}"
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }

# Prints the HTTP status of one GET, or 000 when the connection fails. Runs inside the client pod.
probe='import sys, urllib.request, urllib.error
try:
    print(urllib.request.urlopen(sys.argv[1], timeout=5).status)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception:
    print("000")'

pod="$(kubectl get pods -n "$ns" -l app=denied-client -o name | head -n 1)"
[ -n "$pod" ] || { echo "FAIL: no denied-client pod in $ns: run apply.sh" >&2; exit 1; }
pod="${pod#pod/}"

# 1. The denied client. The pod must run the sidecar first: without it the call would not go through
# the mesh and a failure would say nothing about the deny rule. Then 10 requests, and every one must
# come back 403 (RBAC: access denied). A 2xx, a 503 (the failure switch can be on) and a 000 (no
# sidecar, no DNS) each fail the check, because none of them shows the deny rule at work.
names="$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}')" ||
  { echo "FAIL: could not read pod $pod" >&2; exit 1; }
case " $names " in
  *" kuma-sidecar "*) ;;
  *) bad "$pod has no kuma-sidecar container: restart it after the namespace label and the control plane exist" ;;
esac
denied=0
other=""
for _ in $(seq 1 10); do
  if code="$(kubectl exec -n "$ns" "$pod" -c denied-client -- python3 -I -c "$probe" "$app_url")"; then
    case "$code" in
      403) denied=$((denied + 1)) ;;
      *) other="$other $code" ;;
    esac
  else
    other="$other exec-failed"
  fi
done
echo "denied client, 10 requests: 403=$denied other:${other:- none}"
[ "$denied" -eq 10 ] || bad "the denied client must get 403 on all 10 requests (2xx means let in, 503 the failure switch, 000 no sidecar or DNS), got:$other"

# 2. The admin port is closed to other pods: only a refused connection (000) counts. Any answer,
# a 403 included, means something listens on that address.
app_ip="$(kubectl get pods -n "$ns" -l app=demo-app -o jsonpath='{.items[0].status.podIP}')"
if [ -z "$app_ip" ]; then
  bad "no demo-app pod address to test the admin port"
elif code="$(kubectl exec -n "$ns" "$pod" -c denied-client -- python3 -I -c "$probe" "http://$app_ip:9911/")"; then
  [ "$code" = "000" ] && echo "admin port from the client pod: connection refused" || bad "the admin port answered $code from another pod: it must refuse the connection"
else
  bad "could not run the admin port request inside $pod"
fi

# 3. Scan every MeshTrafficPermission, whatever its labels. Fail on any legacy spec.from entry (the
# from form with action Allow admits whole meshes), on an allow entry with no SPIFFE ID, and on a
# SPIFFE ID that does not reach /ns/<name>/sa/<name> (a wildcard, or a Prefix that stops short).
# At least one allow entry must exist.
read -r total loose legacy <<<"$(kubectl get meshtrafficpermissions -A -o json | jq -r '
  [.items[].spec.rules[]? | .default // {} | ((.allow // [])[], (.allowWithShadowDeny // [])[])] as $a
  | [$a[] | select(((.spiffeID.type // "") == "Exact" or (.spiffeID.type // "") == "Prefix")
                    and ((.spiffeID.value // "") | test("^spiffe://[^*/]+/ns/[^*/]+/sa/[^*/]+$")) | not)] as $loose
  | [.items[] | select((.spec.from // []) | length > 0)] as $legacy
  | "\($a | length) \($loose | length) \($legacy | length)"')"
[ "${total:-0}" -ge 1 ] || bad "no allow rule found: the gateway has nothing that lets it in"
[ "${loose:-0}" -eq 0 ] || bad "${loose} allow entries do not name one caller as spiffe://<trust domain>/ns/<name>/sa/<name> (no wildcard, no short Prefix)"
[ "${legacy:-0}" -eq 0 ] || bad "${legacy} MeshTrafficPermission objects use the from form, which can allow a whole mesh"
echo "allow entries: $total, loose: ${loose:-0}, with spec.from: ${legacy:-0}"

# 4. The gateway path.
url="$(gateway_url)" || exit 1
ok=0
other=0
for _ in $(seq 1 10); do
  line="$(request_once "$url")"
  case "${line%% *}" in
    200) ok=$((ok + 1)) ;;
    503) ;;
    *) other=$((other + 1)) ;;
  esac
done
echo "gateway, 10 requests: 200=$ok other=$other"
[ "$other" -eq 0 ] || bad "$other gateway responses were neither 200 nor 503: the gateway may be denied"
[ "$ok" -ge 1 ] || bad "the gateway never answered 200"

[ "$fail" -eq 0 ] || exit 1
echo "stage 06 OK on $(kubectl config current-context)"
