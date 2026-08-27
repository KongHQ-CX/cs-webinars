# Use Case 7: Central Spend Dashboards & Cost Attribution (Konnect Analytics)

### Situation:
LLM expenditure is historically invisible until the monthly cloud provider invoice arrives. By that point, the money has already been spent, and platform engineering teams cannot easily determine which specific application, team, or route was responsible for the expense. This lack of cost attribution makes it impossible to hold business units accountable, budget accurately, or track down rogue, misconfigured AI endpoints.

### Solution:
Kong Konnect provides a centralized, pre-built **AI/LLM Analytics Dashboard** that addresses this attribution deficit.

### Flow Diagram:
```text
Kong Gateway -> Capture token metrics & provider costs
Kong Gateway -> Add Consumer, Route, and API Key metadata tags
Kong Gateway -> Ship Telemetry -> Kong Konnect Cloud
Konnect Cloud -> Render visual AI/LLM Spend Dashboards
```

By capturing real-time token counts, Kong AI Gateway:
1. Automatically calculates the **actual spend** for every single API request, based on configured provider input/output token tariffs inside the `ai-proxy-advanced` targets.
2. Structures and tags this cost data with metadata identifying the Route, Service, API Key, Consumer, and Provider.
3. Consolidates this transaction log and displays it inside the unified **Konnect Analytics** dashboards.
4. **The result:** Platform teams gain a single dashboard showing total spend over time, token volumes, error rates, and clear spend breakdowns by department or model—fully out-of-the-box and without needing external instrumentation.

---

### Demo:

#### Step 1: Navigating Konnect Analytics
1. Log in to your **Kong Konnect** console.
2. Select the **Analytics** menu from the left-hand navigation sidebar.
3. Click on the pre-built **AI/LLM Summary Dashboard**. This dashboard immediately provides platform-wide insights, including overall request counts, response latency trends, and error rates across all your LLM routes.

---

#### Step 2: Running LLM Spend Explorations
To drill down into specific model costs and determine exactly which departments are driving your bill:
1. Click on the **Explorer** tab inside Konnect Analytics.
2. From the metric dropdown, select **LLM Usage**.
3. Under the **"By"** grouping dropdown, you can filter and pivot by multiple dimensions:
   * **Provider** (OpenAI, Anthropic, Bedrock, etc.)
   * **Model** (gpt-4o, Claude 3.5 Sonnet, etc.)
   * **Routes / Services** (representing different applications or teams)
4. Group by **Total Token Count** and pivot by **Request Model** to see a beautiful, real-time bar chart showing exactly which model variants are consuming the bulk of your budget:
   
   ![LLM Usage by Model](https://github.com/user-attachments/assets/0201be95-fd7f-412f-a8cd-1ec36da7e4e2)

---

#### Step 3: Generating Custom Cost Reports
You can save any live view as an automated, recurring report for your financial audits or executive reviews:
1. Arrange your chart to show **Total Spend over Time, grouped by Consumer (API Key)**.
2. Click **Save as Report** at the top right, and name it `"Weekly AI Spend by Application"`.
3. Click on the **Reports** tab to access pre-configured summaries, such as **"LLM Latency by Model"** or **"LLM Cost by Provider"**:

   ![LLM Latency by Model](https://github.com/user-attachments/assets/d739dc38-3aea-4250-8fbf-3e1ffe3cb018)

---

### Summary:
You cannot optimize what you cannot measure. Konnect Analytics turns Kong AI Gateway's transaction telemetry into a centralized financial audit system. Providing clear spend attribution and transparent dashboards across providers lets platforms allocate budgets accurately, pinpoint cost leakages, and enforce active FinOps cost-governance controls.

---

### References:
* [Kong Konnect Analytics Hub](https://developer.konghq.com)
* [Kong AI Gateway Analytics & Logs Guide](https://developer.konghq.com/plugins/ai-proxy-advanced/)
* [Kong Blog: Announcing AI Gateway Analytics](https://konghq.com/blog/product-releases/announcing-ai-gateway-analytics-dashboards)
