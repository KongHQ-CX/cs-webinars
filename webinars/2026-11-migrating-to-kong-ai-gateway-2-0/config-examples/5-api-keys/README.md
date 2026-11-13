# Applications and API keys used by the example

No identity provider needed: applications authenticate with Kong API keys (`key-auth`). Each application is a
Kong consumer and a member of one tier (consumer group).

| Consumer | Tier | Budget (tokens/min, per provider) | Used for |
|---|---|---|---|
| `app-reporting` | gold | 50,000 | every API check (never rate limited in the tests) |
| `app-chatbot` | silver | 5,000 | native SDK key headers |
| `app-batch` | bronze | 300 | bronze 429 |
| `app-etl` | bronze | 300 | per-consumer budget check (second bronze caller) |

Key headers accepted (`key_names`): `apikey`, plus the headers the native SDKs send so they work unchanged:
`x-api-key` (Anthropic SDK) and `x-goog-api-key` (Gemini SDK). `hide_credentials: true` keeps the Kong key away
from the LLM provider.

Generate keys for your own run:

```bash
for a in APP_REPORTING APP_CHATBOT APP_BATCH APP_ETL; do echo "export DECK_KEY_$a='key-$(openssl rand -hex 16)'"; done
```

decK reads them from the environment (`${{ env "DECK_KEY_APP_REPORTING" }}` in `1-source-3x/kong-316.yaml`).
The converter keeps every existing key: it writes them to `secrets.env` (clear text, from the dump) and references
them as `!secret {source: !env AIGW_APIKEY_<CONSUMER>}`; source that file before `kongctl plan` / `apply`.

Rate limiting counts per consumer: each tier rule in `1-source-3x/kong-316.yaml` matches the consumer with
`partition_by: true` (the `policies` format, 3.14+). The converter copies that 1:1; with the deprecated
`llm_providers` + `identifier: consumer` it would not (runbook step 8).

In production, prefer tokens from your identity provider (openid-connect): they expire, are scoped by audience
and carry group membership. The runbook's step 6 note shows the openid-connect variant.
