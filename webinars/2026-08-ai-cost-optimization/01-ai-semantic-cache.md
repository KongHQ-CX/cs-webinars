# Use Case 1: Semantic Caching (`ai-semantic-cache`)

## Situation:
LLM queries can be highly repetitive. Employees frequently ask similar questions, developers call the same schemas, or customers inquire about common themes. In a traditional caching setup, cache hits only occur when request texts match *exactly* (character-for-character). Because LLM requests contain minor text variations ("How do I prepare a steak?" vs "Tell me how to cook a filet"), traditional caches see a **0% hit rate**, forcing redundant, expensive calls to providers on every single prompt. This incurs severe, unnecessary expenses and drags response times up to several seconds.

## Solution:
Kong AI Gateway's **AI Semantic Cache** plugin solves this by caching queries based on **meaning (semantics)** rather than character matching. 

### Flow Diagram:
```text
Client                 Kong AI Gateway            Embeddings API          Redis VectorDB
  |                            |                           |                       |
  |---- 1. POST "Cook filet" ->|                           |                       |
  |                            |---- 2. Vectorize prompt ->|                       |
  |                            |<--- 3. Return Vector -----|                       |
  |                            |                                                   |
  |                            |---- 4. Cosine similarity query ------------------>|
  |                            |<--- 5. Match Found: "Steak Recipe" (Score: 0.95) -|
  |                            |                                                   |
  |<-- 6. Cached Answer (5ms)--|                                                   |
```

When a prompt is sent:
1. Kong intercepts the prompt and passes it to an **embeddings model** (OpenAI `text-embedding-3-small`) to convert the text into a high-dimensional vector.
2. It queries a **vector database** (Redis) to perform a cosine similarity vector search against previously cached prompts.
3. If the semantic similarity exceeds a preconfigured threshold (e.g. `0.75` or `75%` similarity), Kong instantly returns the cached response.
4. **The result:** The downstream application receives its answer in **under 10 milliseconds** at a **$0.00 provider cost**—completely transparently and without changing a single line of client application code.

---

## decK Configuration:
Here is how the AI Semantic Cache plugin is declared on the `/semantic-cache` route in your `deck.yaml`:

```yaml
      - name: 01-semantic-cache-route
        paths:
          - /semantic-cache
        strip_path: true
        plugins:
          - name: ai-semantic-cache
            config:
              embeddings:
                auth:
                  header_name: Authorization
                  header_value: Bearer ${{ env "OPENAI_API_KEY" }}
                model:
                  provider: openai
                  name: text-embedding-3-small
                  options:
                    upstream_url: https://api.openai.com/v1/embeddings
              vectordb:
                strategy: redis
                threshold: 0.75
                distance_metric: cosine
                redis:
                  host: ${{ env "REDIS_HOST" }}
                  port: ${{ env "REDIS_PORT" }}
          - name: ai-proxy-advanced
            config:
              targets:
                - route_type: llm/v1/chat
                  auth:
                    header_name: Authorization
                    header_value: Bearer ${{ env "OPENAI_API_KEY" }}
                  model:
                    provider: openai
                    name: gpt-4o-mini
                    options:
                      max_tokens: 1024
```

---

## Demo:

### Step 1: Initialize Environment
Ensure your terminal has the configuration credentials loaded:
```bash
source .env
```

### Step 2: Trigger a Cache Miss (First Prompt)
Send a fresh request to cook a steak. Since this is the first query, it will hit the LLM provider directly:
```bash
curl -i -X POST \
  -H "apikey: $DECK_WEBINAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "How do I prepare a steak?"}]}' \
  "$KONG_PROXY_URL/semantic-cache"
```

#### Expected Observability:
* **Response latency:** ~1000ms - 2000ms.
* **Headers returned:** 
  * `X-Cache-Status: miss` (indicates a call was made to OpenAI).

---

### Step 3: Trigger a Semantic Cache Hit (Similar Prompt)
Now, change the wording slightly ("Filet" instead of "Steak") but keep the core meaning identical. A traditional cache would fail here, but Kong's semantic engine will match it:
```bash
curl -i -X POST \
  -H "apikey: $DECK_WEBINAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "How do I prepare a filet?"}]}' \
  "$KONG_PROXY_URL/semantic-cache"
```

#### Expected Observability:
* **Response latency:** **<10ms** (instantaneous).
* **Headers returned:**
  * `X-Cache-Status: hit` (served directly from the local Redis vector database).
  * No upstream latency header is present because **no call was made to OpenAI**!

---

### Step 4: Verify Cache Separation (Unrelated Prompt)
To confirm the threshold doesn't trigger false positives, send an unrelated request:
```bash
curl -i -X POST \
  -H "apikey: $DECK_WEBINAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "How do I prepare a pie?"}]}' \
  "$KONG_PROXY_URL/semantic-cache"
```

#### Expected Observability:
* **Response latency:** ~1000ms - 2000ms (takes time to run inference).
* **Headers returned:**
  * `X-Cache-Status: miss` (correctly recognized as a different topic).

---

## Summary:
By utilizing Kong AI Gateway's semantic caching, organizations can dramatically curb API consumption bills, reduce prompt-processing loops, and deliver an instant response experience to end users—while completely safeguarding central API budgets.

---

### References:
* [Kong AI Semantic Cache Plugin Reference](https://developer.konghq.com/plugins/ai-semantic-cache/)
* [Kong AI Semantic Cache Configuration Reference](https://developer.konghq.com/plugins/ai-semantic-cache/reference/)
* [Kong Blog: Semantic Processing & Vector Search with Kong and Redis](https://konghq.com/blog/engineering/semantic-processing-and-vector-similarity-search-with-kong-and-redis)
