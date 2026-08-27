# Use Case 4: Prompt Compression (`ai-prompt-compressor`)

### Situation:
In RAG (Retrieval-Augmented Generation) applications, system prompts are stuffed with massive chunks of retrieved context documents, chat histories, and long formatting templates. By the time a query is made, the input prompt can easily exceed **50,000 to 100,000 tokens**. Since input tokens typically represent the largest single line item on an enterprise LLM bill, and long prompts increase LLM reasoning latency, companies are heavily overpaying for filler words, repeating phrases, and irrelevant grammatical syntax.

### Solution:
Kong AI Gateway's **AI Prompt Compressor** plugin provides a highly effective mathematical solution. Acting as an inline pre-processor, the gateway intercepts the prompt before forwarding it to the LLM, and compresses the text on the fly.

### Flow Diagram:
```text
Client                 Kong AI Gateway            LLMLingua Compressor        OpenAI
  |                           |                           |                     |
  |--- 1. Bulky RAG prompt -->|                           |                     |
  |    (50,000 tokens)        |---- 2. Compress prompt -->|                     |
  |                           |<--- 3. Dense Prompt ------|                     |
  |                           |     (20,000 tokens)       |                     |
  |                           |                                                 |
  |                           |---- 4. Forward Compressed Prompt -------------->|
  |                           |<--- 5. Get LLM response ------------------------|
  |<- 6. Fast response -------|                                                 |
```

It works by:
1. Identifying low-information and redundant terms (e.g. connectors, filler words, repetitive structures) inside long prompt blocks.
2. Applying mathematical compression ranges. For example, if a prompt is under 100 tokens, it keeps 80% (`value: 0.8`) of the wording, but if it exceeds 100 tokens, it aggressively condenses it to only 30% (`value: 0.3`) of its length.
3. **The result:** Up to a **50% - 70% reduction in prompt token consumption** and **30% reduction in response latency**, preserving complete semantic integrity of the prompt.

---

### decK Configuration:
Here is how the AI Prompt Compressor plugin is declared on the `/prompt-compressor` route in the global `deck.yaml`:

```yaml
      - name: 04-prompt-compressor-route
        paths:
          - /prompt-compressor
        strip_path: true
        plugins:
          - name: ai-prompt-compressor
            config:
              compressor_type: rate
              compressor_url: ${{ env "DECK_COMPRESSOR_URL" }}
              compression_ranges:
                - min_tokens: 20
                  max_tokens: 100
                  value: 0.8
                - min_tokens: 100
                  max_tokens: 1000000
                  value: 0.3
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
```

---

### Demo:

#### Step 1: Initialize Environment
Ensure your terminal has the variables sourced:
```bash
source .env
```

#### Step 2: Query with a Long Prompt (RAG Context Simulation)
Send a query packed with highly redundant, wordy context filler:
```bash
curl -i -X POST \
  -H "apikey: $DECK_WEBINAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "The sky is blue. The sky is indeed blue due to Rayleigh scattering. Sun light has wavelengths. Wavelengths are scattered. Tell me why is the sky blue?"}]}' \
  "$KONG_PROXY_URL/prompt-compressor"
```

##### Expected Observability:
Review the response headers. Kong's custom serverless helper injects real-time prompt-compression diagnostics directly into the terminal output:
* `x-ai-compressor-original-tokens`: `35` (Number of raw tokens received)
* `x-ai-compressor-compressed-tokens`: `29` (Number of tokens after compression)
* `x-ai-compressor-saved-tokens`: `6` (Tokens shaved off in flight!)
* `x-ai-compressor-ratio`: `0.80` (Preserved prompt density ratio)

No container log or metric scrapes are needed—everything is printed directly in your local terminal headers!

---

### Summary:
By offloading prompt token pruning to Kong AI Gateway, platforms can guarantee that expensive frontier LLMs are only receiving the dense, high-information semantic core of prompts. This structurally protects your monthly API budget from the token bloat inherent in modern RAG systems.

---

### References:
* [Kong AI Prompt Compressor Plugin Reference](https://developer.konghq.com/plugins/ai-prompt-compressor/)
* [Kong AI Prompt Compressor Configuration Reference](https://developer.konghq.com/plugins/ai-prompt-compressor/reference/)
* [Kong Developer Hub: AI Prompt Compressor Examples](https://developer.konghq.com/plugins/ai-prompt-compressor/)
