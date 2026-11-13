#!/usr/bin/env bash
# Smoke test for a migrated gateway: run the same requests against the 3.x and the 2.x proxy.
#   BASE_URL=https://ai-316.example.com API_KEY=__REPLACE_ME__ ./smoke-test.sh
#   BASE_URL=https://ai.example.com     API_KEY=__REPLACE_ME__ ./smoke-test.sh
# Optional: GCP_PROJECT and GCP_LOCATION for the native Gemini call (Vertex path).
set -euo pipefail
: "${BASE_URL:?}" "${API_KEY:?}"
P=0; F=0
t() { # name want path body [header]
  local got; got=$(curl -s -m 120 -o /dev/null -w '%{http_code}' -X POST "$BASE_URL$3" -H 'Content-Type: application/json' \
    -H 'anthropic-version: 2023-06-01' ${5:+-H "$5"} -d "$4")
  if [ "$got" = "$2" ]; then P=$((P+1)); echo "PASS $1 ($got)"; else F=$((F+1)); echo "FAIL $1 (want $2, got $got)"; fi
}
K="apikey: $API_KEY"
t "no key -> 401" 401 /openai/v1/chat/completions '{"model":"gpt-5-mini","messages":[{"role":"user","content":"OK?"}]}'
t "OpenAI chat" 200 /openai/v1/chat/completions '{"model":"gpt-5-mini","messages":[{"role":"user","content":"Reply OK"}]}' "$K"
t "OpenAI responses" 200 /openai/v1/responses '{"model":"gpt-5-mini","input":"Reply OK"}' "$K"
t "OpenAI embeddings" 200 /openai/v1/embeddings '{"model":"text-embedding-3-small","input":"hi"}' "$K"
t "Bedrock Claude, OpenAI format" 200 /bedrock/v1/chat/completions '{"model":"us.anthropic.claude-haiku-4-5-20251001-v1:0","max_tokens":16,"messages":[{"role":"user","content":"Reply OK"}]}' "$K"
t "Anthropic Messages (x-api-key)" 200 /anthropic/v1/messages '{"model":"us.anthropic.claude-haiku-4-5-20251001-v1:0","max_tokens":16,"messages":[{"role":"user","content":"Reply OK"}]}' "x-api-key: $API_KEY"
t "Vertex Gemini, OpenAI format" 200 /vertex/v1/chat/completions '{"model":"gemini-2.5-flash","messages":[{"role":"user","content":"Reply OK"}]}' "$K"
t "Vertex embeddings" 200 /vertex/v1/embeddings '{"model":"gemini-embedding-001","input":"hi"}' "$K"
if [ -n "${GCP_PROJECT:-}" ]; then
  t "Gemini native (x-goog-api-key)" 200 "/gemini/v1/projects/$GCP_PROJECT/locations/${GCP_LOCATION:-us-central1}/publishers/google/models/gemini-2.5-flash:generateContent" \
    '{"contents":[{"role":"user","parts":[{"text":"Reply OK"}]}]}' "x-goog-api-key: $API_KEY"
fi
echo "== $P passed, $F failed ($BASE_URL)"
