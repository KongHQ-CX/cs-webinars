# AI Gateway migration report: kong

Generated config: `02-converted` (ai-migrate dev)

| Findings | Count |
|---|---|
| Errors | 0 |
| Warnings | 6 |
| Notes | 4 |

## What clients must change

`Call` is the full path the gateway serves after migration; a pattern segment means the capability is matched by regex. `Body model` is the value a request body's `model` property must carry, or, where marked *(path)*, the model id the URL carries.

1.x ai-proxy-advanced also served requests that carried no model at all. AI Gateway 2.x picks the model from that value, so a model request without it is no longer routed: every client must send `Body model after`.

| Route | Entity | Kind | Called before | Call after | Body model before | Body model after |
|---|---|---|---|---|---|---|
| anthropic-messages | anthropic-messages | model | `/anthropic` | `/anthropic/v1/messages` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |
| bedrock-claude-chat | bedrock-claude-chat | model | `/bedrock/v1/chat/completions` | `/bedrock/v1/chat/completions` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |
| openai-chat | openai-chat | model | `/openai/v1/chat/completions` | `/openai/v1/chat/completions` | `gpt-5-mini` | `gpt-5-mini` |
| openai-embeddings | openai-embeddings | model | `/openai/v1/embeddings` | `/openai/v1/embeddings` | `text-embedding-3-small` | `text-embedding-3-small` |
| openai-responses | openai-responses | model | `/openai/v1/responses` | `/openai/v1/responses` | `gpt-5-mini` | `gpt-5-mini` |
| gemini-native | gemini-native | model | `/gemini` | `/gemini/v1beta/models/(?<model_name>[^:/]+):(?:generateContent\|streamGenerateContent)` | `gemini-2.5-flash` | `gemini-2.5-flash` *(path)* |
| vertex-embeddings | vertex-embeddings | model | `/vertex/v1/embeddings` | `/vertex/v1/embeddings` | `gemini-embedding-001` | `gemini-embedding-001` |
| vertex-gemini-chat | vertex-gemini-chat | model | `/vertex/v1/chat/completions` | `/vertex/v1/chat/completions` | `gemini-2.5-flash` | `gemini-2.5-flash` |

## Secrets to supply

The AI Gateway never returns a write-only field, so these are emitted as `!secret` references. `secrets.env` holds the values recovered from the decK dump; `secrets.env.template` is the same list with the values blanked, for a run where the dump is not the source of truth.

| Environment variable | Fills |
|---|---|
| `AIGW_APIKEY_APP_BATCH` | consumer app-batch api_key |
| `AIGW_APIKEY_APP_CHATBOT` | consumer app-chatbot api_key |
| `AIGW_APIKEY_APP_ETL` | consumer app-etl api_key |
| `AIGW_APIKEY_APP_REPORTING` | consumer app-reporting api_key |

## Findings

| Severity | Code | Entity | Finding | Action |
|---|---|---|---|---|
| warn | global-plugin-dropped | global key-auth | globally scoped key-auth authenticated every route on 1.x; AI Gateway 2.x authenticates per entity, so it was dropped | list every migrated entity under an auth strategy in config/auth_strategies.yaml |
| warn | ssl-verify-forced | policy ai-rate-limiting-advanced | config.redis.ssl_verify was false or null; forced to true because the AI Gateway 2.x data plane rejects a configuration that disables TLS verification | install the upstream CA on the 2.x data planes; the data plane rejects the whole configuration (serving 404 on every route) when any entity disables TLS verification |
| warn | credential-secret-scaffold | consumer app-batch | api key migrated as an environment reference (AIGW_APIKEY_APP_BATCH); without it the gateway would generate a new key and every existing client would break | supply the value through the generated secrets.env before applying |
| warn | credential-secret-scaffold | consumer app-chatbot | api key migrated as an environment reference (AIGW_APIKEY_APP_CHATBOT); without it the gateway would generate a new key and every existing client would break | supply the value through the generated secrets.env before applying |
| warn | credential-secret-scaffold | consumer app-etl | api key migrated as an environment reference (AIGW_APIKEY_APP_ETL); without it the gateway would generate a new key and every existing client would break | supply the value through the generated secrets.env before applying |
| warn | credential-secret-scaffold | consumer app-reporting | api key migrated as an environment reference (AIGW_APIKEY_APP_REPORTING); without it the gateway would generate a new key and every existing client would break | supply the value through the generated secrets.env before applying |
| info | field-dropped | policy ai-rate-limiting-advanced | config fields llm_format are not part of the AI Gateway 2.x ai-rate-limiting-advanced schema, which rejects them; dropped | check that the setting was a default; if it was not, the policy behaves differently on 2.x |
| info | field-dropped | policy ai-rate-limiting-advanced-2 | config fields llm_format are not part of the AI Gateway 2.x ai-rate-limiting-advanced schema, which rejects them; dropped | check that the setting was a default; if it was not, the policy behaves differently on 2.x |
| info | field-dropped | policy ai-rate-limiting-advanced-3 | config fields llm_format are not part of the AI Gateway 2.x ai-rate-limiting-advanced schema, which rejects them; dropped | check that the setting was a default; if it was not, the policy behaves differently on 2.x |
| info | route-fields-dropped | — | route tags aigw-migration were not migrated: the AI Gateway accepts config.route.tags but does not store them, so every later plan would show a change | carry anything you filter on as entity labels instead |

