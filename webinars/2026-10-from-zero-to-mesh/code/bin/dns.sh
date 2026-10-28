#!/usr/bin/env bash
# Point a DNS name at the gateway load balancer (Cloudflare, DNS only, no proxy).
# Usage: dns.sh up|down|check, with CLOUDFLARE_API_TOKEN in the environment of this command only
#   up     create or update the A record with the gateway address (kubectl context: the gateway zone)
#   down   delete the A record (run before teardown so the name never points at a freed address).
#          It needs no cluster and no kubectl.
#   check  print the record and whether the name resolves to the gateway address. It polls the
#          resolver (DNS_CHECK_WAIT seconds, every DNS_CHECK_INTERVAL) because a resolver can answer
#          with the old record until the TTL runs out. It needs dig.
# Env: CLOUDFLARE_API_TOKEN (Zone:Read and Zone:DNS:Edit on the zone),
#      DNS_NAME (required, the record to manage), DNS_ZONE (required, the Cloudflare zone that holds it),
#      DNS_TTL (default 60), DNS_CHECK_WAIT (default 90), DNS_CHECK_INTERVAL (default 5).
# The record must stay DNS only: a proxied record hides the client address from the gateway, and a
# load balancer firewall that allows only some addresses would block Cloudflare.
# The gateway address is read from the ingress Service of the gateway in namespace kong, and must be a
# public IPv4 address. GATEWAY_URL is not used here.
# The token reaches curl on stdin (-H @-), never in argv, and is never printed.
set -euo pipefail
# shellcheck source=../lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

mode="${1:-}"
name="${DNS_NAME:-}"
zone="${DNS_ZONE:-}"
ttl="${DNS_TTL:-60}"
wait_s="${DNS_CHECK_WAIT:-90}"
interval="${DNS_CHECK_INTERVAL:-5}"
resolver="1.1.1.1"
api="https://api.cloudflare.com/client/v4"

case "$mode" in up | down | check) ;; *) echo "usage: dns.sh up|down|check" >&2; exit 2 ;; esac
require_vars CLOUDFLARE_API_TOKEN DNS_NAME DNS_ZONE || exit 2
[[ "$ttl" =~ ^[0-9]+$ ]] || { _err "DNS_TTL must be a number"; exit 2; }
[[ "$wait_s" =~ ^[0-9]+$ ]] || { _err "DNS_CHECK_WAIT must be a number of seconds"; exit 2; }
[[ "$interval" =~ ^[1-9][0-9]*$ ]] || { _err "DNS_CHECK_INTERVAL must be a positive number of seconds"; exit 2; }

# cf <method> <path> [json body]: prints the response body, fails when the API says success is false.
cf() {
  local method="$1" path="$2" body="${3:-}" out
  if [ -n "$body" ]; then
    out="$(printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_API_TOKEN" |
      curl -sS -m 20 -X "$method" -H @- -H 'Content-Type: application/json' --data "$body" "$api$path")" || return 1
  else
    out="$(printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_API_TOKEN" |
      curl -sS -m 20 -X "$method" -H @- "$api$path")" || return 1
  fi
  jq -e '.success == true' <<<"$out" >/dev/null || { _err "Cloudflare $method $path failed: $(jq -c '.errors' <<<"$out" 2>/dev/null)"; return 1; }
  printf '%s' "$out"
}

if [ "$mode" = check ]; then
  command -v dig >/dev/null 2>&1 || { _err "dig is required for check and was not found on PATH"; exit 2; }
fi

zone_id="$(cf GET "/zones?name=$zone" | jq -r '.result[0].id // empty')"
[ -n "$zone_id" ] || { _err "zone $zone not found for this token"; exit 1; }
rec="$(cf GET "/zones/$zone_id/dns_records?type=A&name=$name")"
rec_id="$(jq -r '.result[0].id // empty' <<<"$rec")"
rec_ip="$(jq -r '.result[0].content // empty' <<<"$rec")"

# gateway_ip: the load balancer address of the ingress Service, read from the cluster only.
gateway_ip() {
  local ip
  ip="$(kubectl get svc -n kong -l gateway-operator.konghq.com/dataplane-service-type=ingress \
    -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null)" || ip=""
  [ -n "$ip" ] || { _err "no gateway address: wait for the LoadBalancer of the ingress Service in namespace kong"; return 1; }
  require_public_ipv4 "$ip" || return 1
  printf '%s' "$ip"
}

case "$mode" in
  up)
    require_ctx_1 || exit 1
    ip="$(gateway_ip)" || exit 1
    body="$(jq -nc --arg n "$name" --arg ip "$ip" --argjson ttl "$ttl" \
      '{type: "A", name: $n, content: $ip, ttl: $ttl, proxied: false, comment: "service-mesh-webinar demo gateway"}')"
    if [ -n "$rec_id" ]; then
      cf PUT "/zones/$zone_id/dns_records/$rec_id" "$body" >/dev/null
      echo "updated $name -> $ip (was ${rec_ip:-none})"
    else
      cf POST "/zones/$zone_id/dns_records" "$body" >/dev/null
      echo "created $name -> $ip"
    fi
    ;;
  down)
    if [ -n "$rec_id" ]; then
      cf DELETE "/zones/$zone_id/dns_records/$rec_id" >/dev/null
      echo "deleted $name (was $rec_ip)"
    else
      echo "no record for $name, nothing to delete"
    fi
    ;;
  check)
    [ -n "$rec_id" ] || { _err "no A record for $name"; exit 1; }
    [ "$(jq -r '.result[0].proxied' <<<"$rec")" = "false" ] || { _err "$name is proxied: set it to DNS only"; exit 1; }
    echo "record: $name -> $rec_ip (DNS only)"
    ip="$(gateway_ip)" || exit 1
    [ "$ip" = "$rec_ip" ] || { _err "record points at $rec_ip but the gateway is $ip: run dns.sh up"; exit 1; }
    waited=0
    while :; do
      seen="$(dig +short "$name" "@$resolver" | head -1)" || seen=""
      [ "$seen" = "$ip" ] && break
      if [ "$waited" -ge "$wait_s" ]; then
        _err "$resolver still answers '${seen:-nothing}' after ${waited}s, expected $ip"
        exit 1
      fi
      sleep "$interval"
      waited=$((waited + interval))
    done
    echo "resolves: $name -> $seen"
    ;;
esac
