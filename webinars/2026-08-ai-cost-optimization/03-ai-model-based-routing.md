# Use Case 3: Model-Based Routing (`datakit` + `ai-prompt-decorator`)

### Situation:
While semantic similarity threshold matching is powerful, platform owners sometimes require **explicit, logic-driven classification and orchestration** for routing traffic. For example, they want a fast, compact "router model" to analyze a user's query, explicitly determine the correct target engine (e.g. returning the exact string `"gpt-4o-mini"` or `"gpt-4o"`), and then automatically forward the user’s request to that selected model. Performing this two-hop classification (Classify -> Route) inside client application code requires developers to write custom orchestration loops, distribute keys, and handle target retries.

### Solution:
Kong AI Gateway's **`datakit`** and **`ai-prompt-decorator`** plugins allow platform teams to build a **fully automated, serverless model-based routing engine** directly at the gateway layer—**requiring zero application code changes**.

### Flow Diagram:
```text
Client            Kong (Datakit)         Kong (Classifier Route)       OpenAI (gpt-4o-mini)
  |                     |                         |                              |
  |--- 1. POST Chat --->|                         |                              |
  |                     |--- 2. Call Classifier ->|                              |
  |                     |                         |--- 3. Prepend Router prompt->|
  |                     |                         |<-- 4. Return "gpt-4o-mini"---|
  |                     |<-- 5. Return target ----|                              |
  |                     |                                                        |
  |                     |--- 6. Mutate payload (model: gpt-4o-mini) ------------>|
  |                     |<-- 7. Execute Chat completion -------------------------|
  |<- 8. Chat Answer ---|                                                        |
```

Here is how the automated orchestration workflow operates:
1. **The Client Call:** The client sends their standard chat prompt to a single, unified endpoint: `/model-routing`.
2. **The Datakit Interception:** The gateway's `datakit` plugin intercepts the request and launches a sequential pipeline inside the proxy context:
   * **Node 1 (Extract):** Extracts the user's prompt using a lightweight `jq` parser.
   * **Node 2 (Classify Call):** Executes an internal HTTP call to a local classifier endpoint: `/model-selection`.
3. **The Classifier Endpoint (`/model-selection`):** 
   * This endpoint is decorated by **`ai-prompt-decorator`**, prepending strict system routing rules (*"You are a model router. Analyze the user's prompt and recommend the most appropriate model. Return ONLY ONE of these exact strings: 'gpt-4o-mini' for simple tasks, or 'gpt-4o' for complex tasks."*).
   * A high-speed target (`gpt-4o-mini`) processes this prepended query and returns *only* the chosen model string.
4. **The Datakit Assembly:**
   * **Node 3 (Parse):** Uses `jq` to parse the classifier's response and extract the clean model name.
   * **Node 4 (Mutate):** Updates the user's original request payload in memory, dynamically injecting the selected model into the JSON body (`model: selected`).
5. **The Final Delivery:** Kong's `ai-proxy-advanced` plugin receives the mutated request, matches the selected model against its target `model_alias` configurations, and securely forwards the query to the chosen provider.

---

### decK Configuration:
Here is how the two-hop routing topology is declared in the global `deck.yaml`:

```yaml
      # ------------------------------------------------------------------------
      # Route 3a: Model-Based Routing - Classifier Endpoint
      # ------------------------------------------------------------------------
      - name: 03-model-selector-route
        paths:
          - /model-selection
        strip_path: true
        plugins:
          - name: ai-prompt-decorator
            config:
              llm_format: openai
              prompts:
                prepend:
                  - role: system
                    content: >
                      You are an intelligent model router. Analyze the user's prompt and recommend the most
                      appropriate model for the task. Return ONLY ONE of these exact strings,
                      nothing else: "gpt-4o-mini" for simple tasks, or "gpt-4o" for complex tasks requiring deeper reasoning.
          - name: ai-proxy-advanced
            config:
              response_streaming: deny
              targets:
                - route_type: llm/v1/chat
                  auth:
                    header_name: Authorization
                    header_value: Bearer ${{ env "DECK_OPENAI_API_KEY" }}
                  model:
                    provider: openai
                    name: gpt-4o-mini

      # ------------------------------------------------------------------------
      # Route 3b: Model-Based Routing - Orchestration Endpoint
      # ------------------------------------------------------------------------
      - name: 03-model-routing-route
        paths:
          - /model-routing
        strip_path: true
        plugins:
          - name: datakit
            config:
              nodes:
                - { name: EXTRACT_PROMPT, type: jq, input: request.body, jq: '({"messages": .messages})' }
                - { name: CALL_MODEL_SELECTOR, type: call, url: "http://localhost:8000/model-selection",
                    method: POST, inputs: { body: EXTRACT_PROMPT } }
                - { name: EXTRACT_MODEL, type: jq, inputs: { body: CALL_MODEL_SELECTOR.body },
                    jq: '.body.choices[0].message.content | gsub("^\\s+|\\s+$"; "")' }
                - { name: UPDATE_REQUEST, type: jq, inputs: { original: request.body, selected: EXTRACT_MODEL },
                    output: service_request.body, jq: '.original + {model: .selected}' }
          - name: ai-proxy-advanced
            config:
              response_streaming: allow
              targets:
                - route_type: llm/v1/chat
                  auth:
                    header_name: Authorization
                    header_value: Bearer ${{ env "DECK_OPENAI_API_KEY" }}
                  model:
                    provider: openai
                    name: gpt-4o-mini
                    model_alias: gpt-4o-mini
                - route_type: llm/v1/chat
                  auth:
                    header_name: Authorization
                    header_value: Bearer ${{ env "DECK_OPENAI_API_KEY" }}
                  model:
                    provider: openai
                    name: gpt-4o
                    model_alias: gpt-4o
```

---

### Demo:

#### Step 1: Initialize Environment
Ensure your terminal has the variables sourced:
```bash
source .env
```

#### Step 2: Test Case A - Conversational Prompt (Automated Down-routing)
Send a simple task to the orchestrator endpoint `/model-routing`:
```bash
curl -i -X POST \
  -H "apikey: $DECK_WEBINAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello there! How are you?"}]}' \
  "$KONG_PROXY_URL/model-routing"
```

##### Expected Observability:
The background orchestration takes place instantly. Under the hood:
1. `/model-selection` is called.
2. The classifier returns `"gpt-4o-mini"`.
3. `datakit` mutates the request payload to `{ "model": "gpt-4o-mini", ... }`.
4. `ai-proxy-advanced` executes the final delivery on `gpt-4o-mini`.

* **Response Headers:** `x-kong-llm-model: openai/gpt-4o-mini`
* **Response Body:**
  ```json
  "model": "gpt-4o-mini-2024-07-18"
  ```

---

#### Step 3: Test Case B - Engineering/Complex Prompt (Automated Up-routing)
Now, send a task requiring reasoning, such as a complete sorting algorithm:
```bash
curl -i -X POST \
  -H "apikey: $DECK_WEBINAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Write a highly optimized quicksort algorithm in Rust with benchmark tests."}]}' \
  "$KONG_PROXY_URL/model-routing"
```

##### Expected Observability:
1. `/model-selection` is called with the complex query.
2. The classifier realizes this is a complex, technical request and returns `"gpt-4o"`.
3. `datakit` updates the request payload to `{ "model": "gpt-4o", ... }`.
4. `ai-proxy-advanced` automatically routes and delivers the request to the high-capacity **`gpt-4o`** engine:

* **Response Headers:** `x-kong-llm-model: openai/gpt-4o`
* **Response Body:**
  ```json
  "model": "gpt-4o-2024-05-13"
  ```

---

### Summary:
Model-Based Routing turns your gateway into an active, intelligent routing coprocessor. By chaining the `datakit` orchestration pipeline with an explicit classifier endpoint, companies can systematically analyze, sort, and deliver user queries to the most cost-effective and accurate model target—all transparently to client code.

---

### References:
* [Kong Model-Based Routing Cookbook](https://developer.konghq.com/cookbooks/model-based-routing/)
* [Kong Datakit Plugin Reference](https://docs.konghq.com/hub/kong-inc/datakit/)
* [Kong AI Prompt Decorator Plugin Hub](https://docs.konghq.com/hub/kong-inc/ai-prompt-decorator/)
