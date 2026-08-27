# Use Case 2: Semantic Routing (`ai-proxy-advanced`)

### Situation:
In most enterprises, developers send *all* requests to the most powerful, high-capacity models available (like `gpt-4o`) because they are "best". However, up to **80% of routine corporate prompts** (e.g. classification, translation, or basic query parsing) can be solved perfectly by compact, inexpensive models (like `gpt-4o-mini`). Because developers hard-code model targets inside their client applications, companies lose millions of dollars on model over-provisioning. Furthermore, when provider pricing changes or a new, cheaper model is released, changing the model requires editing, testing, and redeploying the application code across dozens of teams.

### Solution:
Kong AI Gateway's **AI Proxy Advanced** plugin introduces a smart mediation tier. Instead of routing requests directly, client applications send generic LLM prompts to a unified route on the gateway.

### Flow Diagram:
```text
Client                 Kong AI Gateway              Redis DB                 Providers
  |                           |                         |                         |
  |---- 1. POST "Hello" ----->|                         |                         |
  |                           |-- 2. Embed & Lookup --->|                         |
  |                           |<- 3. Best Match: mini --|                         |
  |                           |                                                   |
  |                           |---- 4. Route to gpt-4o-mini ($0.15/M) ----------->|
  |                           |<--- 5. Return mini response ----------------------|
  |<- 6. Return response -----|                                                   |
```

Kong's **Semantic Balancer** then handles routing dynamically by evaluating the **semantic intent** of each incoming user prompt:
1. **At deployment time:** The descriptions of our models are embedded and stored in the Redis vector database (e.g., General knowledge model vs. Complex reasoning model).
2. **At request time:** Kong intercepts the prompt, converts it to an embedding vector, and calculates the similarity against each model’s description.
3. **The routing decision:** 
   * A simple, low-complexity question (e.g., *"What is the capital of Italy?"*) is automatically routed to the ultra-cheap **`gpt-4o-mini`** model ($0.15/M tokens).
   * A complex, technical query (e.g., *"Write a complete multi-threaded server in Rust..."*) is automatically routed to the premium **`gpt-4o`** model ($2.50/M tokens).
4. **The result:** Downstream applications consume exactly the resources they need, slashing enterprise LLM costs on the fly without any code changes.

---

### decK Configuration:
Here is how the semantic targets are declared on the `/proxy-advanced` route in the global `deck.yaml`:

```yaml
      - name: 02-proxy-advanced-route
        paths:
          - /proxy-advanced
        strip_path: true
        plugins:
          - name: ai-proxy-advanced
            config:
              embeddings:
                auth:
                  header_name: Authorization
                  header_value: Bearer ${{ env "DECK_OPENAI_API_KEY" }}
                model:
                  provider: openai
                  name: text-embedding-3-small
                  options:
                    upstream_url: https://api.openai.com/v1/embeddings
              vectordb:
                strategy: redis
                dimensions: 1536
                threshold: 1
                distance_metric: cosine
                redis:
                  host: ${{ env "DECK_REDIS_HOST" }}
                  port: ${{ env "DECK_REDIS_PORT" }}
              balancer:
                algorithm: semantic
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
                  description: "Use this target for simple, routine, conversational questions, general knowledge, greetings, and basic text formatting."
                - route_type: llm/v1/chat
                  auth:
                    header_name: Authorization
                    header_value: Bearer ${{ env "DECK_OPENAI_API_KEY" }}
                  model:
                    provider: openai
                    name: gpt-4o
                    options:
                      max_tokens: 1024
                  description: "Use this target for advanced, complex tasks requiring deep reasoning, mathematics, logic puzzles, coding, computer science, and software engineering."
```

---

### Demo:

#### Step 1: Initialize Environment
Ensure your terminal has the variables sourced:
```bash
source .env
```

#### Step 2: Test Case A - Conversational Prompt (Simple Intent)
Send a basic greeting / informational request to the unified `/proxy-advanced` route:
```bash
curl -i -X POST \
  -H "apikey: $DECK_WEBINAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello! Say hi."}]}' \
  "$KONG_PROXY_URL/proxy-advanced"
```

##### Expected Observability:
Review the response payload. The gateway correctly maps the simple intent to the general conversational model description and routes the prompt to **`gpt-4o-mini`**:
* **Response Headers:** `x-kong-llm-model: openai/gpt-4o-mini`
* **Response Body:**
  ```json
  "model": "gpt-4o-mini-2024-07-18"
  ```

---

#### Step 3: Test Case B - Complex Coding Prompt (Reasoning Intent)
Now, send a highly complex engineering prompt requesting a recursive algorithm:
```bash
curl -i -X POST \
  -H "apikey: $DECK_WEBINAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Write a complete multithreaded socket server in Rust with graceful shutdown handling."}]}' \
  "$KONG_PROXY_URL/proxy-advanced"
```

##### Expected Observability:
Because the prompt semantic vector aligns strongly with the logical reasoning and computer science model description, Kong automatically promotes and routes the request to the high-capacity **`gpt-4o`** model:
* **Response Headers:** `x-kong-llm-model: openai/gpt-4o`
* **Response Body:**
  ```json
  "model": "gpt-4o-2024-05-13"
  ```

---

### Summary:
AI Proxy Advanced's semantic load balancing ensures that you are only paying for premium, resource-intensive frontier models when the complexity of the query actually demands it. Simple, routine, and lightweight requests are automatically triaged to cheap, ultra-fast model tiers, resulting in automated, highly-effective cost containment.

---

### References:
* [Kong AI Proxy Advanced Plugin Reference](https://developer.konghq.com/plugins/ai-proxy-advanced/)
* [Kong Semantic Balancing Examples](https://developer.konghq.com/plugins/ai-proxy-advanced/examples/semantic/)
* [Kong AI Proxy Advanced Configuration Reference](https://developer.konghq.com/plugins/ai-proxy-advanced/reference/)
