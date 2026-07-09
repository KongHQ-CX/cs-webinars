#!/usr/bin/env bash
# Sends 210 sequential requests and validates:
#   - Requests 1-200  → HTTP 200
#   - Requests 201-210 → HTTP 429
set -euo pipefail

: "${LB_IP:?Set LB_IP to the DataPlane LoadBalancer IP}"

HOST="${GATEWAY_HOST:-api.kong-air.example.com}"
TOTAL="${TOTAL_REQUESTS:-210}"
LIMIT="${RATE_LIMIT:-200}"
PASS_COUNT=0
FAIL_COUNT=0
FIRST_429=""

echo "==> Burst test: $TOTAL requests → expecting 429 from request $((LIMIT + 1))"
echo ""

for i in $(seq 1 "$TOTAL"); do
  CODE=$(curl -sk -o /dev/null -w '%{http_code}' \
    -H "Host: $HOST" \
    "https://${LB_IP}/flights")

  if [[ "$i" -le "$LIMIT" ]]; then
    # Expect 200
    if [[ "$CODE" == "200" ]]; then
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      echo "  UNEXPECTED at request $i: HTTP $CODE (expected 200)"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  else
    # Expect 429
    if [[ "$CODE" == "429" ]]; then
      PASS_COUNT=$((PASS_COUNT + 1))
      if [[ -z "$FIRST_429" ]]; then
        FIRST_429=$i
        echo "  First 429 at request $i — PASS"
      fi
    else
      echo "  UNEXPECTED at request $i: HTTP $CODE (expected 429)"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  fi

  # Print progress every 50 requests.
  if [[ $((i % 50)) -eq 0 ]]; then
    echo "  Progress: $i/$TOTAL (pass=$PASS_COUNT fail=$FAIL_COUNT)"
  fi
done

echo ""
echo "==> Burst test results"
echo "    Total:  $TOTAL"
echo "    Pass:   $PASS_COUNT"
echo "    Fail:   $FAIL_COUNT"
echo "    First 429 at request: ${FIRST_429:-none}"

if [[ "$FAIL_COUNT" -eq 0 ]] && [[ -n "$FIRST_429" ]]; then
  echo ""
  echo "PASS: Rate limiting working correctly"
else
  echo ""
  echo "FAIL: $FAIL_COUNT unexpected responses"
  exit 1
fi
