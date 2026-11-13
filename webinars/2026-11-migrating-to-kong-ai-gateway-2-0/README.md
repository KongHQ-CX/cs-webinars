# Migrating to Kong AI Gateway 2.0

This folder holds everything the webinar used. With it you can repeat the live migration in your own Konnect
organization: load a typical AI configuration onto a Kong Gateway 3.x control plane, migrate it to Kong AI Gateway
2.x with the official converter, and send the same requests to both gateways. Nothing here needs another repository.

[Watch the recording](https://konghq.com/events/webinars/migrating-to-kong-ai-gateway-2-0)

## What is in the download

| File | What it is |
|---|---|
| `migration-runbook.html` | **Start here.** Open it in a browser and fill in your settings; every command updates as you type. Part 1 loads the example onto your 3.x gateway, part 2 migrates it and tests both gateways. Nothing leaves your browser, and secrets are never stored. Prefer a terminal? The same steps are below in [Run it by hand](#run-it-by-hand) |
| `.env.example` | Every variable the runbook, [Run it by hand](#run-it-by-hand) and `smoke-test.sh` read, with `__REPLACE_ME__` for each value you supply |
| `smoke-test.sh` | The same 9 requests against any gateway: `BASE_URL=https://<proxy> API_KEY=<consumer key> ./smoke-test.sh` |
| `config-examples/1-source-3x/kong-316.yaml` | The 3.x configuration (decK): 8 AI routes, key-auth, 4 consumers in three tiers. Credentials and keys come from `DECK_*` variables |
| `config-examples/2-converter-config/` | Converter input: the target AI Gateway and the key-auth strategy |
| `config-examples/3-converted-raw/` | What `kongctl convert ai-gateway` writes for the example, with `migration-report.md` (credentials shown as `__REPLACE_ME__`) |
| `config-examples/4-final/` | What gets applied: the converter output with the credentials as `!secret` references |
| `config-examples/5-api-keys/README.md` | The applications, their tiers and how the keys migrate |
| `Migrating-to-Kong-AI-Gateway-2.0-Webinar.pdf` | The slide deck from the session. [Watch the recording](https://konghq.com/events/webinars/migrating-to-kong-ai-gateway-2-0) |
| `Migrating-to-Kong-AI-Gateway-2.0-Webinar.html` | The same deck as a page, with clickable references (arrow keys to move, N for notes) |

## What you need

- A Konnect organization and a personal access token for it.
- A Kong Gateway 3.x hybrid control plane with a connected data plane (tested with 3.16.0.2; the tier format needs
  3.14 or later), and a Kong AI Gateway 2.x with a connected data plane and no configuration yet (tested with 2.3.1).
  No AI Gateway yet? Create one in Konnect and connect a data plane with the setup instructions Konnect shows. The
  example only touches 3.x entities tagged `aigw-migration`, so any 3.x control plane you can test on works.
- `kongctl` with the converter extension, `deck`, `yq` (mikefarah, v4), `jq` and `openssl` on your PATH. Tested with
  kongctl 1.28.0, converter v0.6.0 and decK 1.70.0. The GitHub CLI (`gh`) is optional, to check for a newer converter.
- Credentials for the providers you want to try: an OpenAI API key, an Amazon Bedrock API key (Claude Haiku 4.5 in
  us-east-1) and a Google Vertex AI service-account key. Missing one? Delete that service from `kong-316.yaml`.

Neither data plane needs extra settings: the provider credentials travel with the configuration.

## The example

| Route | Provider and model | API |
|---|---|---|
| `/openai/v1/chat/completions` | OpenAI gpt-5-mini | OpenAI chat |
| `/openai/v1/responses` | OpenAI gpt-5-mini | OpenAI Responses |
| `/openai/v1/embeddings` | OpenAI text-embedding-3-small | embeddings |
| `/bedrock/v1/chat/completions` | Bedrock, Claude Haiku 4.5 | OpenAI format |
| `/anthropic/v1/messages` | Bedrock, Claude Haiku 4.5 | native Anthropic Messages |
| `/vertex/v1/chat/completions` | Vertex AI, Gemini 2.5 Flash | OpenAI format |
| `/vertex/v1/embeddings` | Vertex AI, gemini-embedding-001 | embeddings |
| `/gemini/v1/projects/<p>/locations/<l>/publishers/google/models/<m>:generateContent` | Vertex AI, Gemini 2.5 Flash | native Gemini |

| Consumer | Tier | Tokens per minute |
|---|---|---|
| `app-reporting` | gold | 50,000 |
| `app-chatbot` | silver | 5,000 |
| `app-batch` | bronze | 300 |
| `app-etl` | bronze | 300 |

Every 3.x entity carries the tag `aigw-migration`, and the decK file selects on it, so loading and removing the
example leaves anything else on your control plane alone.

## Run it by hand

The same 13 steps as `migration-runbook.html`, as plain shell commands. Every value comes from `.env`, so the
commands run as they are. Use bash or zsh, and run every step in the same terminal.

### 1. Tools and gateways

```bash
brew install kong/kongctl/kongctl kong/deck/deck yq jq        # or the install method for your OS
kongctl install extension Kong/kongctl-ext-aigw-converter --yes
kongctl version; kongctl convert ai-gateway version; deck version
```

You need a Kong Gateway 3.x hybrid control plane and a Kong AI Gateway 2.x, each with a connected data plane (see
[What you need](#what-you-need)).

### 2. Environment variables

Work in a folder outside this download: the dump and the raw converter output hold your credentials in clear text.

```bash
export KIT=~/2026-11-migrating-to-kong-ai-gateway-2-0        # where you unzipped this download
mkdir -p ~/aigw-migration/secrets && cd ~/aigw-migration && chmod 700 secrets
[ -f .env ] || { cp "$KIT/.env.example" .env; chmod 600 .env; }
# edit .env now: replace every __REPLACE_ME__ (the comments say what each value is)
set -a; source .env; set +a
DECK_KONNECT=(--konnect-token "$KONNECT_PAT" --konnect-addr "$KONNECT_ADDR" --konnect-control-plane-name "$SRC_CP")
```

Keep values in single quotes in `.env`: a `Bearer ...` value contains a space.

### 3. Check access

```bash
deck gateway ping "${DECK_KONNECT[@]}"
kongctl get ai-gateways -o json | jq -r '.[] | .name + "  (" + .display_name + ")"'
kongctl get ai-gateway nodes --gateway-name "$TARGET_GW" -o json | jq -r '.[] | "\(.hostname) \(.version) \(.config_sync.state)"'
```

Expect your organization, your AI Gateway in the list, and its data plane in `STATE_IN_SYNC`.

### 4. Load the 3.x configuration

```bash
cp "$KIT/config-examples/1-source-3x/kong-316.yaml" .
deck gateway validate "${DECK_KONNECT[@]}" kong-316.yaml
deck gateway diff "${DECK_KONNECT[@]}" kong-316.yaml | tail -4
deck gateway sync "${DECK_KONNECT[@]}" kong-316.yaml | tail -4       # only touches entities tagged aigw-migration
```

Wait about 30 seconds for the data plane to sync, then make a first call. Expect an answer, then `401` without a key:

```bash
curl -s "$SRC_URL/openai/v1/chat/completions" -H "apikey: $DECK_KEY_APP_REPORTING" -H 'Content-Type: application/json' \
  -d '{"model":"gpt-5-mini","messages":[{"role":"user","content":"In one sentence: what is an AI gateway?"}]}' | jq -r '.choices[0].message.content'
curl -s -o /dev/null -w '%{http_code}\n' "$SRC_URL/openai/v1/chat/completions" -H 'Content-Type: application/json' -d '{}'
```

### 5. Export the 3.x configuration

```bash
mkdir -p 01-dump
# --select-tag keeps the export to the example; for a real migration, export without it
deck gateway dump "${DECK_KONNECT[@]}" --select-tag aigw-migration -o 01-dump/kong.yaml --yes
chmod 600 01-dump/kong.yaml
yq '[.services[].routes[]] | length' 01-dump/kong.yaml                                   # 8 routes
yq -o=json -I=0 '.plugins[] | select(.name == "key-auth") | .config.key_names' 01-dump/kong.yaml   # key names to keep
```

### 6. Converter input

The target AI Gateway and the auth strategy that replaces the global key-auth plugin (the same files as
`config-examples/2-converter-config/`, with your names):

```bash
mkdir -p config
# keep the display name your AI Gateway already has
TARGET_GW_DISPLAY=$(kongctl get ai-gateways -o json | jq -r --arg n "$TARGET_GW" '.[] | select(.name == $n) | .display_name')
cat > config/gateway.yaml <<EOF
_defaults:
  kongctl:
    namespace: $TARGET_GW
ai_gateways:
  - ref: $TARGET_GW
    name: $TARGET_GW
    display_name: "$TARGET_GW_DISPLAY"
    description: Migrated from Kong Gateway 3.x control plane $SRC_CP
    min_runtime_version: "2.3"
EOF
cat > config/auth_strategies.yaml <<'EOF'
auth_strategies:
  - ref: api-key
    name: api-key
    display_name: API key
    type: key-auth
    config:
      key_names: [apikey, x-api-key, x-goog-api-key]
      hide_credentials: true
      key_in_header: true
      key_in_query: true
    models: ['*']
EOF
# hand the existing AI Gateway to kongctl (once; "already has namespace label" means it is done)
kongctl adopt ai-gateway "$TARGET_GW" --namespace "$TARGET_GW"
```

### 7. Convert

```bash
rm -rf 02-converted
kongctl convert ai-gateway --input 01-dump/kong.yaml --config config --out 02-converted --namespace-prefix aigw-migration
sed -n '/^| Route |/,/^$/p' 02-converted/migration-report.md        # what clients must change
```

Expect `findings: 0 error(s)`. The warnings are explained in `config-examples/3-converted-raw/migration-report.md`.

### 8. Review: tier budgets and credentials

```bash
rm -rf 03-final && cp -R 02-converted 03-final
mv 03-final/secrets.env secrets/converted-keys.env && rm -f 03-final/secrets.env.template && chmod 600 secrets/converted-keys.env
set -a; source secrets/converted-keys.env; set +a                     # the AIGW_APIKEY_* values for plan and apply

# tier budgets: every rule must match the provider and the consumer, both with partition_by: true
yq -o=json -I=0 '.ai_gateway_policies[] | select(.type == "ai-rate-limiting-advanced") | {(.name): .config.policies[0].match}' 03-final/policies.yaml

# credentials: reference the provider credentials from the environment instead of copying them
yq -i '
  with(.ai_gateway_model_providers[] | select(.type == "openai") | .config.auth.headers[0].value; . = {"source": "DECK_OPENAI_AUTH"} | . tag = "!secret" | .source tag = "!env") |
  with(.ai_gateway_model_providers[] | select(.type == "bedrock") | .config.auth.headers[0].value; . = {"source": "DECK_BEDROCK_AUTH"} | . tag = "!secret" | .source tag = "!env") |
  with(.ai_gateway_model_providers[] | select(.type == "gemini") | .config.auth.service_account_json; . = {"source": "DECK_GCP_SA_JSON"} | . tag = "!secret" | .source tag = "!env")' 03-final/providers.yaml
grep -rlE 'sk-|bedrock-api-key-|PRIVATE KEY' 03-final || echo "no secrets in 03-final"
```

The example's tiers already carry both partitions. If a rule has no `consumer` match (tiers converted from the older
`llm_providers` format), add one before you plan, or the whole tier shares one budget:

```bash
yq -i '(.ai_gateway_policies[] | select(.type == "ai-rate-limiting-advanced") | .config.policies[].match) |=
  (map(select(.type == "provider") |= . + {"partition_by": true}) + [{"type": "consumer", "partition_by": true}])' 03-final/policies.yaml
```

### 9. Plan and apply

```bash
kongctl plan --mode apply -f 03-final --output-file plan.json
kongctl diff --plan plan.json | less                                  # review: models, providers, policies, consumers
kongctl apply --plan plan.json --auto-approve
kongctl plan --mode apply -f 03-final --output-file plan.json && kongctl diff --plan plan.json | tail -2   # expect "No changes"
kongctl get ai-gateway nodes --gateway-name "$TARGET_GW" -o json | jq -r '.[] | "\(.hostname) \(.version) \(.config_sync.state)"'
```

Keep `plan.json` out of `03-final`: a plan inside the config folder makes later plans report stale results.

### 10. Test both gateways

Wait about 30 seconds after the apply. Expect `9 passed, 0 failed` on both:

```bash
export GCP_PROJECT="$DECK_GCP_PROJECT" GCP_LOCATION="$DECK_GCP_LOCATION"
for u in "$SRC_URL" "$DST_URL"; do echo "== $u"; BASE_URL=$u API_KEY="$DECK_KEY_APP_REPORTING" "$KIT/smoke-test.sh" | tail -1; done
```

One call by hand on each, with the rate-limit headers (same names on both):

```bash
for u in "$SRC_URL" "$DST_URL"; do echo "== $u"
  curl -s -D - -o /dev/null "$u/anthropic/v1/messages" -H "x-api-key: $DECK_KEY_APP_CHATBOT" -H 'anthropic-version: 2023-06-01' \
    -H 'Content-Type: application/json' -d '{"model":"us.anthropic.claude-haiku-4-5-20251001-v1:0","max_tokens":40,"messages":[{"role":"user","content":"Hi"}]}' \
    | grep -iE '^(HTTP|x-kong-llm-model|x-ai-ratelimit-(limit|remaining)-minute-policy)'
done
```

### 11. Per-consumer budgets

Use up `app-batch`'s bronze budget (300 tokens per minute), then call once as `app-etl`, which is in the same tier.
Expect `429` for `app-batch` within a few calls and `200` for `app-etl`. Wait a minute after the other tests first.

```bash
for u in "$SRC_URL" "$DST_URL"; do echo "== $u"
  for i in $(seq 1 12); do
    c=$(curl -s -o /dev/null -w '%{http_code}' "$u/openai/v1/chat/completions" -H "apikey: $DECK_KEY_APP_BATCH" -H 'Content-Type: application/json' \
          -d '{"model":"gpt-5-mini","messages":[{"role":"user","content":"In three sentences, explain what an API gateway does."}]}')
    echo "app-batch $c"; [ "$c" = 429 ] && break
  done
  curl -s -o /dev/null -w 'app-etl %{http_code}\n' "$u/openai/v1/chat/completions" -H "apikey: $DECK_KEY_APP_ETL" \
    -H 'Content-Type: application/json' -d '{"model":"gpt-5-mini","messages":[{"role":"user","content":"Reply OK"}]}'
done
```

`429` for `app-etl` means the tier shares one budget: add the consumer partition (step 8), then plan and apply again.

### 12. Cut over

1. Re-plan (step 9) and expect "No changes".
2. Tell client owners what changes: the client table from step 7, and the rate-limit header names.
3. Freeze changes on the 3.x control plane, or run steps 5 to 9 again just before the switch.
4. Move traffic (DNS or load balancer) from the 3.x proxy to the AI Gateway proxy, and keep 3.x running.
5. Watch errors and token usage on both in Konnect analytics. Rate-limit counters start fresh on 2.x.

Rollback means pointing traffic back to the 3.x proxy: nothing on 3.x was changed.

### 13. Clean up (test runs only)

```bash
# 3.x: everything tagged aigw-migration
deck gateway reset "${DECK_KONNECT[@]}" --select-tag aigw-migration --force
# 2.x: the migrated entities (models first, providers last)
GW_ID=$(kongctl get ai-gateways -o json | jq -r --arg n "$TARGET_GW" '.[] | select(.name == $n) | .id')
for k in models consumer-groups consumers policies auth-strategies model-providers; do
  for id in $(curl -s -H "Authorization: Bearer $KONNECT_PAT" "$KONNECT_ADDR/v1/ai-gateways/$GW_ID/$k?page%5Bsize%5D=100" | jq -r '.data[].id'); do
    curl -s -o /dev/null -X DELETE -H "Authorization: Bearer $KONNECT_PAT" "$KONNECT_ADDR/v1/ai-gateways/$GW_ID/$k/$id"
  done; echo "$k removed"
done
```

Then delete `~/aigw-migration` (it holds your credentials) and revoke the tokens you created for the test.

## What to expect

1. **The converter does most of the work.** One model per 3.x route (paths and model names kept), one provider per
   credential, the consumer groups with their policies, and the consumers with their existing keys. Clients change
   nothing.
2. **Global key-auth** is declared once as an auth strategy (step 6).
3. **Credentials:** the example holds provider credentials inline, so one command in step 8 references them as
   `!secret` before planning. With vault references in 3.x, which is the better choice in production, they carry over
   unchanged. Treat the dump and the raw converter output as secret.
4. **Rate-limit tiers carry over 1:1**, because the example writes them in the `policies` format, partitioned by
   provider and consumer. If your tiers use the older `llm_providers` format, move them to `policies` on 3.x first.
5. **Clients send `model`**, as listed in `migration-report.md`.

If something doesn't convert the way you expect, review the report, add the manual step it calls for, or reach out
to Kong support or your CSM.

## References

- [Migrate to AI Gateway 2.x](https://developer.konghq.com/ai-gateway/v2-migration-guide/) (official migration guide)
- [AI Gateway 2.x concepts](https://developer.konghq.com/ai-gateway/ai-gateway-v2-concepts/) (v1 to v2 entity mapping)
- [Kong AI Gateway changelog](https://developer.konghq.com/ai-gateway/changelog/)
- [kongctl-ext-aigw-converter](https://github.com/Kong/kongctl-ext-aigw-converter)
- [kongctl docs](https://developer.konghq.com/kongctl/) and [GitHub](https://github.com/Kong/kongctl)
- [decK docs](https://developer.konghq.com/deck/) and [GitHub](https://github.com/Kong/deck)
