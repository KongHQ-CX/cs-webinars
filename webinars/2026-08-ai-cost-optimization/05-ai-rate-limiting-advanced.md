# Use Case 5: Token and Cost-Based Rate Limiting (`ai-rate-limiting-advanced`)

### Situation:
Traditional API rate limiting (requests/sec or transactions/minute) is blind to data density and LLM workloads. A single user can send one massive, 128K prompt that forces a multi-dollar inference, while another user can send 50 tiny 5-token requests costing pennies. Under traditional request-based rate limiting, both are treated identically. This lets rogue applications trigger runaway token-consumption bills, exhaust provider rate ceilings, and lock out critical production services.

### Solution:
Kong AI Gateway's **AI Rate Limiting Advanced** plugin introduces financial intelligence to access limits. 

### Flow Diagram:
```text
Client                 Kong AI Gateway              Redis Store               OpenAI
  |                           |                          |                      |
  |---- 1. POST chat -------->|                          |                      |
  |                           |--- 2. Fetch current cost>|                      |
  |                           |<-- 3. Return remaining --|                      |
  |                           |                                                 |
  |                           |-- [ Budget OK? ]                                |
  |                           |   Yes -> Call OpenAI -------------------------->|
  |                           |   No  -> Return HTTP 429 (Blocked!)             |
  |<- 4. Response / 429 ------|                                                 |
```

Instead of counting HTTP connections:
1. It calculates the **actual token consumption** of each prompt and model response (e.g. input tokens and output tokens).
2. It translates those token counts into **real-time monetary costs** (in dollars or virtual currency units) based on target provider tariff cards (using `tokens_count_strategy: cost`).
3. It enforces strict cost budgets per team, department, API key, or consumer.
4. **The result:** Once a user reaches their allocated financial ceiling, the gateway safely blocks further requests with a standard `HTTP 429 Too Many Requests` status, protecting the enterprise from runaway AI spend.

---

### decK Configuration:
Here is how the cost-based rate limiter is declared on the `/rate-limiting-advanced` route in the global `deck.yaml`:

```yaml
      - name: 05-rate-limiting-advanced-route
        paths:
          - /rate-limiting-advanced
        strip_path: true
        plugins:
          - name: ai-rate-limiting-advanced
            config:
              tokens_count_strategy: cost
              hide_client_headers: false
              llm_providers:
                - name: openai
                  limit:
                    - 0.00001  # Ultra-small cost budget (one-hundredth of a cent!)
                  window_size:
                    - 60  # 60 second window
          - name: ai-proxy-advanced
            config:
              targets:
                - route_type: llm/v1/chat
                  auth:
                    header_name: Authorization
                    header_value: Bearer ${{ env "DECK_OPENAI_API_KEY" }}
                  model:
                    provider: openai
                    name: gpt-4o-mini
                    options:
                      max_tokens: 1024
                      input_cost: 0.15
                      output_cost: 0.60
```

---

### Demo:

#### Step 1: Initialize Environment
Ensure your terminal has the variables sourced:
```bash
source .env
```

#### Step 2: Trigger the Rate Limit Loop (Rapid Cost Breach)
To demonstrate financial rate limiting instantly on screen, we execute a rapid loop of 3 simple queries using `"hi"`. Given that each query costs roughly `0.000008` based on our custom model tariffs, our ultra-small budget limit of `0.00001` will be breached on the very second call:

```bash
for i in {1..3}; do
  echo "==> Call $i"
  curl -i -X POST \
    -H "apikey: $DECK_WEBINAR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"messages": [{"role": "user", "content": "hi"}]}' \
    "$KONG_PROXY_URL/rate-limiting-advanced"
done
```

##### Expected Observability:
The terminal output will display the full HTTP headers and JSON responses for each call:

```text
==> Call 1
HTTP/2 200 OK
content-type: application/json
x-ai-ratelimit-limit-minute-openai: 0.00001
x-ai-ratelimit-remaining-minute-openai: 0.000002  # Budget decreases

{
  "choices": [{"message": {"content": "Hello!"}}],
  "usage": { "prompt_tokens": 12, "completion_tokens": 9, "total_tokens": 21 }
}

==> Call 2
HTTP/2 200 OK
content-type: application/json
x-ai-ratelimit-limit-minute-openai: 0.00001
x-ai-ratelimit-remaining-minute-openai: -0.000006  # Budget fully exhausted!

{
  "choices": [{"message": {"content": "Hello!"}}],
  "usage": { "prompt_tokens": 12, "completion_tokens": 9, "total_tokens": 21 }
}

==> Call 3
HTTP/2 429 Too Many Requests
content-type: application/json
x-ai-ratelimit-limit-minute-openai: 0.00001
x-ai-ratelimit-remaining-minute-openai: -0.000006  # Immediately rejected!

{
  "message": "AI token rate limit exceeded for provider(s): openai"
}
```
---

### Summary:
AI Rate Limiting Advanced turns Kong AI Gateway into a real-time FinOps firewall. Enforcing constraints based on tokens and actual pricing budgets instead of raw requests secures platform resources, prevents invoice shock, and establishes isolated, fair budgets across all teams.

---

### References:
* [Kong AI Rate Limiting Advanced Plugin Reference](https://developer.konghq.com/plugins/ai-rate-limiting-advanced/)
* [Kong AI Rate Limiting Advanced Configuration Reference](https://developer.konghq.com/plugins/ai-rate-limiting-advanced/reference/)
* [Kong Blog: Financial Governance and Budget Controls for LLMs](https://konghq.com/blog/engineering/llm-financial-governance-budget-controls)
