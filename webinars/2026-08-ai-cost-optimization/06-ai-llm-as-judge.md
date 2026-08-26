# Use Case 6: Quality Metrics with LLM-as-a-Judge (`ai-llm-as-judge`)

### Situation:
When attempting to optimize costs, platform teams routinely want to downgrade their default applications from premium models (like `gpt-4o`) to lightweight, cheap models (like `gpt-4o-mini`), saving **up to 95% in infrastructure spend**. However, business units and application owners frequently resist this change, arguing that the cheaper model is "not accurate enough" or will compromise user experience. Historically, there was no way to systematically measure and compare model output quality in production.

### Solution:
Kong AI Gateway's **AI LLM as Judge** plugin provides a systematic, data-driven framework to resolve this quality debate. 

### Flow Diagram:
```text
Client            Kong AI Gateway             gpt-4o-mini (Primary)          gpt-4o-mini (Judge)
  |                     |                              |                              |
  |-- 1. POST chat ---->|                              |                              |
  |                     |--- 2. Call Primary --------->|                              |
  |                     |<-- 3. Fast Answer -----------|                              |
  |<- 4. Return Answer -|                                                             |
  |                     |                                                             |
  |                     |--- 5. (ASYNC) Call Judge with original prompt & mini reply->|
  |                     |<-- 6. Return Score (1-100) ---------------------------------|
  |                     |                                                             |
  |                     |--- 7. Publish `llm_accuracy: 95` to logs/Collector -------->|
```

It works by:
1. Routing user queries to the cheaper, "primary" model (`gpt-4o-mini`) as requested.
2. In the background (asynchronously), the gateway intercepts a configured percentage of requests (e.g. `sampling_rate: 1` or 100%) and forwards the prompt and the cheap model's response to a separate **"Judge" model** (like `gpt-4o-mini`).
3. The Judge evaluates the response based on a preconfigured system prompt (checking for helpfulness, tone, and accuracy) and assigns an objective score between **1 and 100**.
4. These scores are emitted in the gateway's structured logs (`ai.proxy.ai-llm-as-judge.usage.llm_accuracy`).
5. **The result:** Platform teams can prove empirically that the cheaper model maintains an acceptable quality rating (e.g. consistently scoring >85/100) before making the downgrade permanent.

---

### decK Configuration:
Here is how the LLM as a Judge and local `file-log` serialization loop are declared on the `/llm-as-judge` route in the global `deck.yaml`:

```yaml
      - name: 06-llm-as-judge-route
        paths:
          - /llm-as-judge
        strip_path: true
        plugins:
          - name: post-function
            config:
              body_filter:
                - |
                  local metrics = ngx.ctx.ai_llm_metrics
                  if metrics and metrics.llm_accuracy then
                    kong.log.set_serialize_value("ai-llm-as-judge", { accuracy = metrics.llm_accuracy })
                  end
          - name: file-log
            config:
              path: /tmp/file.log
              reopen: true
          - name: ai-llm-as-judge
            config:
              prompt: |
                You are a strict, objective AI auditor. Evaluate the answer's correctness and formatting.
                Return a single numeric score between 1 and 100 representing accuracy. Do NOT output any explanations, tags, or text.
              sampling_rate: 1
              llm:
                auth:
                  header_name: Authorization
                  header_value: Bearer ${{ env "DECK_OPENAI_API_KEY" }}
                model:
                  provider: openai
                  name: gpt-4o-mini
                  options:
                    temperature: 1
                    max_tokens: 5
                route_type: llm/v1/chat
```

---

### Demo:

#### Step 1: Open a Split-Terminal and Stream Judge Scores (Terminal 2)
For an interactive, real-time live demo, open a **second terminal window** (split-screen), source your variables, and run a continuous stream of the `/tmp/file.log` file directly out of your active Kubernetes pod, parsing the custom Judge accuracy score using `jq`:

```bash
source .env
kubectl -n "$K8S_NAMESPACE" exec "$K8S_DEPLOYMENT" -c proxy -- tail -f /tmp/file.log | jq --unbuffered '."ai-llm-as-judge"'
```
*(Keep this Terminal 2 open and visible throughout the rest of the demo steps!)*

---

#### Step 2: Trigger Test Case A - Conversational Prompt (Terminal 1)
In your main Terminal 1 window, send a simple informational request to the `/llm-as-judge` route:
```bash
curl -i -X POST \
  -H "apikey: $DECK_WEBINAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "What is the capital of Italy?"}]}' \
  "$KONG_PROXY_URL/llm-as-judge"
```

##### Expected Observability (Terminal 2 Stream):
Terminal 1 receives the fast `gpt-4o-mini` response immediately. Simultaneously, your background streaming Terminal 2 instantly prints the Judge’s accurate evaluation:
```json
{
  "accuracy": 100
}
```
* **Analysis:** The Judge model awards a perfect score of **`100`** because `gpt-4o-mini` returned the accurate answer ("Rome") cleanly and concisely!

---

#### Step 3: Trigger Test Case B - Complex Math Query (Terminal 1)
Now, let's test the primary model's ability to solve complex step-by-step logic. Send a Pythagorean math request in Terminal 1:
```bash
curl -i -X POST \
  -H "apikey: $DECK_WEBINAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Prove the Pythagorean theorem."}]}' \
  "$KONG_PROXY_URL/llm-as-judge"
```

##### Expected Observability (Terminal 2 Stream):
While Terminal 1 displays the complete step-by-step mathematical reasoning, your streaming Terminal 2 instantly appends the new evaluation score:
```json
{
  "accuracy": 100
}
```
* **Analysis:** Even with complex multi-step arithmetic, the Judge awards a **`100`** (or high `98+` score) indicating that the cheap `gpt-4o-mini` is highly capable, accurate, and completely reliable for advanced tasks. This data-driven score gives platform teams absolute confidence to implement model downgrades and pocket up to **95% in cost savings**!

---

### Summary:
LLM as a Judge provides the data-driven telemetry needed to confidently downgrade target models and reduce costs by up to 95%. By measuring production-level model quality, platform teams can make cost optimization decisions backed by objective quality scores.

---

### References:
* [Kong AI LLM as a Judge Plugin Reference](https://developer.konghq.com/plugins/ai-llm-as-judge/)
* [Kong AI LLM as a Judge Configuration Reference](https://developer.konghq.com/plugins/ai-llm-as-judge/reference/)
* [Kong Developer Hub: AI LLM as a Judge Examples](https://developer.konghq.com/plugins/ai-llm-as-judge/)
* [Kong How-To Guide: Compare LLM Models Accuracy](https://developer.konghq.com/how-to/compare-llm-models-accuracy/)
