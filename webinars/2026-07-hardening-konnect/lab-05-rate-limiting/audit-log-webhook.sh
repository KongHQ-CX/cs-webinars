#!/usr/bin/env bash
# Configures the Konnect audit log SIEM webhook.
set -euo pipefail

: "${KONNECT_PAT:?Set KONNECT_PAT}"
: "${SIEM_WEBHOOK_URL:?Set SIEM_WEBHOOK_URL to your SIEM ingest endpoint}"

KONNECT_REGION="${KONNECT_REGION:-us}"
BASE_URL="https://${KONNECT_REGION}.api.konghq.com/v2"
AUTH="Authorization: Bearer ${KONNECT_PAT}"

echo "==> Configuring audit log webhook to: $SIEM_WEBHOOK_URL"
RESP=$(curl -sf -X PUT "${BASE_URL}/audit-log-webhook" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d "{
    \"endpoint\": \"${SIEM_WEBHOOK_URL}\",
    \"enabled\": true,
    \"log_format\": \"json\",
    \"authorization\": \"Bearer ${KONNECT_PAT}\"
  }")
echo "$RESP" | python3 -m json.tool

echo ""
echo "==> Making a config change to generate an audit log event..."
# Update the rate-limit plugin description to trigger a config change event.
PLUGIN_ID=$(cat .rate-limit-plugin-id 2>/dev/null || echo "")
if [[ -n "$PLUGIN_ID" ]]; then
  curl -sf -X PATCH \
    "${BASE_URL}/control-planes/${KONNECT_CONTROL_PLANE_ID}/core-entities/plugins/${PLUGIN_ID}" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d '{"tags": ["lab5", "rate-limit", "audit-verified"]}' \
    | python3 -m json.tool
else
  echo "WARN: .rate-limit-plugin-id not found. Make a manual config change to generate audit events."
fi

echo ""
echo "==> Waiting 10s for event ingestion..."
sleep 10

echo "==> Fetching recent audit logs"
curl -sf "${BASE_URL}/audit-logs?page_size=5" -H "$AUTH" | python3 -m json.tool
