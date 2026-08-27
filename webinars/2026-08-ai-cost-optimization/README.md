# Kong AI Gateway: Cost Optimization Webinar Demo Suite

Welcome to the **Kong AI Gateway Cost Optimization Webinar Demo Suite**. This repository contains all of the configuration examples, deployment artifacts, and step-by-step guides presented during the session.

Platform engineering teams, API platform owners, and financial managers can use these examples to establish transparent, active cost governance across every application and team in their organization—**without rewriting a single line of application code**.

---

## Folder Structure

All webinar artifacts are self-contained and located in this directory:

```text
cost-optimization-webinar/
├── README.md                         # This Master Guide & Setup Instructions
├── .env.example                      # Environment variables template file
├── .gitignore                        # Git ignore local environment files
├── deck.yaml                         # Unified decK gateway topology (1 service, 7 routes)
├── 01-ai-semantic-cache.md           # Use Case 1: Semantic Caching with Redis Vectordb
├── 02-ai-semantic-routing.md         # Use Case 2: Semantic Model Routing
├── 03-ai-model-based-routing.md      # Use Case 3: Model-Based (Intelligent) Routing
├── 04-ai-prompt-compressor.md         # Use Case 4: Prompt Token Length Compression
├── 05-ai-rate-limiting-advanced.md   # Use Case 5: Token & Cost-Based Rate Limiting Budgets
├── 06-ai-llm-as-judge.md             # Use Case 6: Quality Metrics with LLM-as-a-Judge
└── 07-konnect-analytics.md           # Use Case 7: Centralized Spend Dashboards & Attribution
```

---

## Use Cases Covered

1. **[Semantic Caching (Use Case 1)](01-ai-semantic-cache.md)**: Matches prompts by *meaning* rather than exact characters. Returns matching answers instantly from Redis Cache at **$0 cost** and **<10ms latency**.
2. **[Semantic Model Routing (Use Case 2)](02-ai-semantic-routing.md)**: Dynamically routes incoming prompts to optimal models based on the semantic intent of the query matched against target descriptions.
3. **[Model-Based Routing (Use Case 3)](03-ai-model-based-routing.md)**: Implements a serverless model classifier and orchestrator loop inside the gateway using `datakit` and `ai-prompt-decorator` to explicitly classify and up-route/down-route queries.
4. **[Prompt Compression (Use Case 4)](04-ai-prompt-compressor.md)**: Intelligently summarizes or shortens long prompt blocks or RAG contexts, reducing up to 50% of the input bill.
5. **[Token and Cost-Based Rate Limiting (Use Case 5)](05-ai-rate-limiting-advanced.md)**: Enforces real-time dollar-spend or token consumption budgets per consumer, team, or department.
6. **[LLM as a Judge Quality Scoring (Use Case 6)](06-ai-llm-as-judge.md)**: Asynchronously grades cheaper model responses using a high-capacity model (GPT-4o), ensuring data-driven optimization.
7. **[Centralized Spend Dashboards (Use Case 7)](07-konnect-analytics.md)**: Explores Kong Konnect's built-in AI/LLM Analytics Dashboards to audit overall consumption, filter by department, and track cost attribution.

---

## Getting Started

Follow these steps to deploy the complete webinar topology to your own Kong Gateway instance.

### Prerequisites

1. **Kong Gateway (Enterprise Edition)** running and connected to Kong Konnect.
2. **decK CLI** installed on your local machine.
3. **Redis Server** (standalone or Redis Stack) running and accessible to the Kong Data Plane nodes (required for Semantic Cache, Semantic Routing, and Rate Limiting).
4. **OpenAI API Key** to send model requests.

### Step 1: Configure Environment Variables

1. Copy the `.env.example` template:
   ```bash
   cp .env.example .env
   ```
2. Open `.env` in your editor and populate your credentials:
   * `DECK_OPENAI_API_KEY`: Your OpenAI Bearer Token.
   * `DECK_KONNECT_TOKEN`: Your Konnect Personal Access Token.
   * `DECK_CP_NAME`: The name of your Konnect control plane (defaults to `ai-cost-optimization`).
   * `DECK_REDIS_HOST` & `DECK_REDIS_PORT`: Redis service coordinates.
   * `KONG_PROXY_URL`: Public endpoint of your Kong Gateway proxy.
3. Source the variables in your active terminal session:
   ```bash
   source .env
   ```

### Step 2: Deploy to Konnect Control Plane

Use `decK` to synchronize the complete 7-route webinar configuration to your Konnect Control Plane:

```bash
deck gateway sync deck.yaml \
  --konnect-addr "$DECK_KONNECT_ADDR" \
  --konnect-token "$DECK_KONNECT_TOKEN" \
  --konnect-control-plane-name "$DECK_CP_NAME"
```

### Step 3: Run the Demos

You are now ready! Open each numbered Markdown file (from `01-` to `07-`) to learn the core concepts, inspect the specific plugin configuration snippets, and execute live testing commands using `curl`.

## Reference Guide & Reading List

This document consolidates all of the official documentation, market research papers, industry statistics, and technical cookbooks referenced throughout the **Kong AI Gateway Cost Optimization Webinar**.

---

### 1. Industry Research & Market Statistics

These references compile the core "theory," unit economics, and spend surge projections discussed during the introductory portion of the webinar:

*   **[Gartner Forecasts Worldwide AI Market to Grow 63% (Gartner Press Release)](https://www.gartner.com/en/newsroom/press-releases/2026-07-20-gartner-forecasts-worldwide-ai-platforms-and-models-market-to-grow-63-percent-in-2026)**  
    *Highlights the rapid expansion and scale of model adoption, reinforcing the need for platform-level FinOps safeguards.*
*   **[The Cost of Intelligence: How CIOs Can Manage AI Demand at Scale (McKinsey & Company)](https://www.mckinsey.com/capabilities/quantumblack/our-insights/the-cost-of-intelligence-how-cios-can-manage-ai-demand-at-scale)**  
    *Provides a strategic roadmap for engineering leaders to transition from naive model access to active, gateway-mediated financial governance.*
*   **[RouteLLM: Learning to Route LLMs with Preference Data (Research Paper - arXiv:2406.18665)](https://arxiv.org/abs/2406.18665)**  
    *An outstanding research paper on optimizing LLM costs by using preference datasets to train lightweight, high-speed routing classifiers—the exact conceptual basis of our Scenario 3 (Model-Based Routing).*

---

### 2. Kong AI Gateway Plugin Reference Documentation

Official, up-to-date documentation on Kong's developer hub for each of the cost-optimization plugins demonstrated during the live scenarios:

*   **[Kong AI Semantic Cache Plugin Hub](https://developer.konghq.com/plugins/ai-semantic-cache/)**  
    *Learn how to set up vector-database caching based on semantic meaning.*
*   **[Kong AI Semantic Cache Configuration Reference](https://developer.konghq.com/plugins/ai-semantic-cache/reference/)**  
    *Direct config schema parameters for text-embeddings and Redis VectorDB coordinates.*
*   **[Kong AI Proxy Advanced Plugin Hub](https://developer.konghq.com/plugins/ai-proxy-advanced/)**  
    *Details cost-aware routing, weighted load-balancing, and semantic balancer models.*
*   **[Kong Semantic Balancing Examples](https://developer.konghq.com/plugins/ai-proxy-advanced/examples/semantic/)**  
    *Hands-on walkthroughs for matching prompt vectors against target model descriptions.*
*   **[Kong AI Proxy Advanced Configuration Reference](https://developer.konghq.com/plugins/ai-proxy-advanced/reference/)**  
    *Complete, target-by-target configuration schema and cost-logging parameters.*
*   **[Kong AI Prompt Compressor Plugin Reference](https://developer.konghq.com/plugins/ai-prompt-compressor/)**  
    *Learn about inline prompt token compression rates, ranges, and microservice setups.*
*   **[Kong AI Prompt Compressor Configuration Reference](https://developer.konghq.com/plugins/ai-prompt-compressor/reference/)**  
    *Config schema definitions for LLMLingua compression algorithms.*
*   **[Kong AI Rate Limiting Advanced Plugin Reference](https://developer.konghq.com/plugins/ai-rate-limiting-advanced/)**  
    *Guide for setting up cost-based and token-based rate-limiting ceilings.*
*   **[Kong AI Rate Limiting Advanced Configuration Reference](https://developer.konghq.com/plugins/ai-rate-limiting-advanced/reference/)**  
    *Config parameters for defining provider tariff cards and sliding-window budgets.*
*   **[Kong AI LLM as a Judge Plugin Reference](https://developer.konghq.com/plugins/ai-llm-as-judge/)**  
    *Examines how to orchestrate asynchronous background model output quality evaluations.*
*   **[Kong AI LLM as a Judge Configuration Reference](https://developer.konghq.com/plugins/ai-llm-as-judge/reference/)**  
    *Parameters for sampling rates, scoring prompts, and target judge model profiles.*

---

### 3. Serverless Orchestration & Advanced Flow Plugins

Guides and specifications for the serverless `post-function` helper and `datakit` routing plugins used in the advanced demo configurations:

*   **[Kong Datakit Plugin Reference](https://developer.konghq.com/plugins/datakit/)**  
    *Examines the core JSON node execution pipeline used for building serverless API flows.*
*   **[Kong AI Prompt Decorator Plugin Hub](https://developer.konghq.com/plugins/ai-prompt-decorator/)**  
    *Learn how to automatically prepend or append system instructions to incoming prompts.*
*   **[Kong Serverless Functions (Post-Function) Plugin Reference](https://developer.konghq.com/plugins/post-function/)**  
    *Reference guide for executing custom, secure Lua scripts inside Nginx proxy phases.*

---

### 4. Architectural Blueprints & GitOps Tools

Blueprints and toolchains used to operationalize and deploy the webinar topology declaratively:

*   **[Kong Model-Based Routing Cookbook](https://developer.konghq.com/cookbooks/model-based-routing/)**  
    *Step-by-step cookbook for chaining prompt classifiers with the datakit orchestration engine.*
*   **[Kong How-To Guide: Compare LLM Models Accuracy](https://developer.konghq.com/how-to/compare-llm-models-accuracy/)**  
    *A production-grade blueprint for running local file-log evaluations to score primary model quality.*
*   **[decK CLI Installation & Gateway GitOps Hub](https://developer.konghq.com)**  
    *The official portal for installing, deploying, and managing your declarative GitOps states.*
