#!/usr/bin/env bash
# Creates the flights/bookings Services + Routes directly via the Konnect
# Admin API. Replaces the operator-managed KongService/KongRoute CRDs —
# there is no controller reconciling Kubernetes objects into Konnect here;
# this talks to Konnect directly, the same way the Konnect UI would.
#
# strip_path: true — Kong strips the matched path prefix before forwarding.
# Each Service carries the matching path prefix so the upstream still
# receives the full path:
#   GET /flights/KA101 → strip /flights → service path /flights + /KA101
#                      → upstream GET /flights/KA101 ✓
#
# Apply after:
#   - helm/values.yaml is installed and the DataPlane pods are Running
#   - backend/kong-air.yaml (upstream service must exist)
set -euo pipefail

: "${KONNECT_PAT:=<type your Konnect PAT>}"
: "${KONNECT_CONTROL_PLANE_ID:=<type your Konnect Control plane ID>}"

KONNECT_REGION="${KONNECT_REGION:-in}"
GATEWAY_HOST="${GATEWAY_HOST:-api.kong-air.example.com}"
BASE_URL="https://${KONNECT_REGION}.api.konghq.com/v2/control-planes/${KONNECT_CONTROL_PLANE_ID}/core-entities"
AUTH="Authorization: Bearer ${KONNECT_PAT}"

# curl -f hides the response body on HTTP errors, turning failures into
# opaque silent exits under `set -e`. This helper prints status + body on
# failure so problems are diagnosable instead of swallowed.
konnect_api() {
  local method="$1" url="$2" data="${3:-}"
  local resp status body
  if [[ -n "$data" ]]; then
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "$AUTH" -H "Content-Type: application/json" -d "$data")
  else
    resp=$(curl -s -w '\n%{http_code}' -X "$method" "$url" -H "$AUTH")
  fi
  status=$(echo "$resp" | tail -1)
  body=$(echo "$resp" | sed '$d')
  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    echo "FAIL: $method $url -> HTTP $status" >&2
    echo "$body" >&2
    return 1
  fi
  echo "$body"
}

# List endpoints paginate (meta.page.number/size/total, default page size
# appears to be 10 — see lab-03's roles response and lab-05's page_size=5
# usage for the flat page_size/page_number query param convention this API
# actually uses, not JSON:API-style page[number]). A plain unpaginated GET
# only returns page 1 and can silently miss entities once the total count
# exceeds the page size — request a page size large enough that pagination
# never realistically kicks in for this lab's entity counts.
konnect_list_all() {
  local url="$1"
  local sep="?"
  [[ "$url" == *"?"* ]] && sep="&"
  konnect_api GET "${url}${sep}page_size=200"
}

create_service_and_route() {
  local name="$1" path="$2" methods="$3"
  local service_config="{
      \"name\": \"${name}-service\",
      \"host\": \"kong-air.kong-air.svc.cluster.local\",
      \"port\": 80,
      \"protocol\": \"http\",
      \"path\": \"${path}\",
      \"retries\": 5,
      \"connect_timeout\": 60000,
      \"write_timeout\": 60000,
      \"read_timeout\": 60000
    }"
  # protocols includes both http and https: base installs HTTP-only, but
  # every lab from Lab 1 onward switches the DP to HTTPS-only. A route that
  # only allowed "http" 404s against an HTTPS-only DP even though the DP
  # itself is healthy — Kong simply has no matching route for the https
  # protocol. Allowing both means this script doesn't need to change between
  # base and the labs.
  local route_config="{
      \"name\": \"${name}-route\",
      \"protocols\": [\"http\", \"https\"],
      \"hosts\": [\"${GATEWAY_HOST}\"],
      \"paths\": [\"${path}\"],
      \"methods\": [${methods}],
      \"strip_path\": true,
      \"preserve_host\": false
    }"

  # The ?name= query filter is unreliable against this API (it was observed
  # returning the first service in the list regardless of the name given,
  # causing bookings-service to resolve to flights-service's ID). Fetch every
  # page of the full list and filter by exact name match in Python instead —
  # a single unpaginated GET only sees page 1 and can miss entities once the
  # total count exceeds the page size.
  local existing_service_id
  existing_service_id=$(konnect_list_all "${BASE_URL}/services" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [s for s in d.get('data', []) if s.get('name') == '${name}-service']
print(matches[0]['id'] if matches else '')
" 2>/dev/null || echo "")

  local service_id
  if [[ -n "$existing_service_id" ]]; then
    # Not calling PUT here: Konnect's core-entities PUT rejects a body whose
    # "name" matches the entity's own current name with a self-referential
    # uniqueness error ("name (type: unique) constraint failed"). The
    # service's config (host/port/protocol/path) never changes between labs
    # anyway — only the route's allowed protocols do — so there's nothing to
    # update here; just reuse the existing service's ID.
    echo "==> Service '${name}-service' already exists ($existing_service_id) — reusing, no changes needed"
    service_id="$existing_service_id"
  else
    echo "==> Creating Service: ${name}-service"
    local service_resp
    service_resp=$(konnect_api POST "${BASE_URL}/services" "$service_config")
    echo "$service_resp" | python3 -m json.tool
    service_id=$(echo "$service_resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  fi

  echo ""
  # Same pagination caveat as the service lookup above — walk every page so
  # a stray duplicate route from an earlier run isn't missed.
  local all_routes
  all_routes=$(konnect_list_all "${BASE_URL}/routes")
  local existing_route_ids
  existing_route_ids=$(echo "$all_routes" | python3 -c "
import sys, json
d = json.load(sys.stdin)
matches = [r['id'] for r in d.get('data', []) if r.get('name') == '${name}-route']
print('\n'.join(matches))
" 2>/dev/null || echo "")

  if [[ -n "$existing_route_ids" ]]; then
    # PUT with the route's own current "name" 400s with the same
    # self-referential uniqueness error as the Service PUT above — Konnect's
    # core-entities PUT appears to validate uniqueness against all entities
    # rather than excluding the one being replaced. Unlike the service,
    # the route's config genuinely needs to change here (protocols), so
    # skipping isn't an option — delete and recreate instead, which reuses
    # the exact same POST path already proven to work for fresh creation.
    # Delete ALL matches, not just the first: earlier runs (before pagination
    # was handled here) could have left duplicate '${name}-route' entities
    # that this script never found and thus never cleaned up.
    while IFS= read -r dup_id; do
      [[ -z "$dup_id" ]] && continue
      echo "==> Route '${name}-route' already exists ($dup_id) — deleting"
      konnect_api DELETE "${BASE_URL}/routes/${dup_id}" >/dev/null
    done <<< "$existing_route_ids"
    echo "==> Recreating '${name}-route' with updated config"
    konnect_api POST "${BASE_URL}/services/${service_id}/routes" "$route_config" | python3 -m json.tool
  else
    echo "==> Creating Route: ${name}-route"
    konnect_api POST "${BASE_URL}/services/${service_id}/routes" "$route_config" | python3 -m json.tool
  fi
  echo ""
}

create_service_and_route "flights" "/flights" '"GET"'
create_service_and_route "bookings" "/bookings" '"GET", "POST", "DELETE"'

echo "==> Services + Routes created"
