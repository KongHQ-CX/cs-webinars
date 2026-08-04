# AI and API — Hands-On Demo

One backend service. Different stages of connectivity. The service never changes —
only the layer in front of it does. By the end you've rebuilt the whole arc of
the webinar.

| Stage | What you show | What's in front of the API |
|------:|---------------|----------------------------|
| 1 | The raw API | Nothing — curl hits it directly |
| 2 | The control point | Kong Gateway (routing only), on Konnect |
| 3 | Models talk, APIs act | OpenAI function calling → Kong → API |
| 4 | One protocol, not N×M | MCP server(Kong) → API |
| 5 | Governance | Kong with auth, rate limits, logging |

Every Kong deployment here is a **Kong Konnect data plane** 
You run one data-plane container (`docker-compose.yml`) that
connects to your Konnect control plane over mTLS, and you push each stage's
configuration to the control plane with decK. Stages use OpenAI for the model
calls.

---

## 0. Set up from scratch

You need three things: Homebrew, Python 3.11+, and Docker. If you already have
them, skip to "Get the project running."

**Homebrew** (the macOS package manager):
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
Follow the printed instructions to add `brew` to your PATH.

**Python and Docker Desktop:**
```bash
brew install python@3.11
brew install --cask docker
```
Then open Docker Desktop once from Applications so the engine starts. Confirm:
```bash
python3 --version     # 3.11 or newer
docker --version
docker compose version
```

**Get the project running.** From the `demo/` folder:
```bash
cd demo
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
cp .env.example .env
```

Open `.env` and paste your OpenAI API key into `OPENAI_API_KEY`.

This demo runs entirely on **Kong Konnect** — every gateway is a Konnect data
plane. You need these up front (all free):

- **decK**: `brew install kong/deck/deck`
- A **Kong Konnect** account and personal access token (https://cloud.konghq.com).
  Put the token in `.env` as `KONNECT_TOKEN`, and set `KONNECT_CONTROL_PLANE` to
  your control plane's name.
- One `/etc/hosts` line so your host and the data-plane container resolve Keycloak
  (stage 6) identically:
  ```bash
  echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts
  ```

Keep the virtual environment active (`source .venv/bin/activate`) in every
terminal you open.

### Start the Konnect data plane (used by every stage)

In Konnect, open **Gateway Manager → your control plane → + New Data Plane Node →
Docker**. Save the generated certificate to `konnect/tls.crt` and the private key
to `konnect/tls.key`, and copy the control-plane and telemetry endpoints into
`.env` (`KONNECT_CP_*`, `KONNECT_TP_*`). Then bring the data plane up once — it
stays running for the whole demo:
```bash
docker compose up -d          # docker-compose.yml is the Konnect data plane
```
The proxy is on `:8000` (HTTP) and `:8443` (HTTPS). It holds no local config — you
push each stage's config to Konnect with decK. Define a small helper that carries
your Konnect flags, and you'll use `ksync <file>` throughout:
```bash
set -a; source .env; set +a
ksync() { deck gateway sync --konnect-token "$KONNECT_TOKEN" \
  --konnect-control-plane-name "$KONNECT_CONTROL_PLANE" "$@"; }
```
`deck gateway sync` is declarative: each `ksync <file>` makes the control plane
match that file, and the data plane picks up the change in seconds.

---

## Stage 1 — The raw API

Start the backend. Leave it running in its own terminal.
```bash
python -m uvicorn app:app --reload --port 8080
```

In a second terminal, call it directly — no gateway, no AI:
```bash
curl -s localhost:8080/products | python3 -m json.tool
curl -s localhost:8080/inventory/SKU-1024 | python3 -m json.tool
curl -s -X POST localhost:8080/orders \
  -H 'content-type: application/json' \
  -d '{"sku":"SKU-1024","quantity":1}' | python3 -m json.tool
```

You'll see products, a stock level, and an order confirmation with an order ID.

**The point:** this is the contract. A stable operation with a known input and a
known output. Everything else in this demo is about *who* gets to call it and
*how* you control them. Note the API has no idea who's calling — no auth, no
limits, no log of who did what. Hold that thought for stage 5.

---

## Stage 2 — Put a control point in front of it

Keep the backend running. Your Konnect data plane is already up from setup, but
it has no routes yet. Push the service and route to Konnect:
```bash
ksync kong.yaml
```
`kong.yaml` is a decK file: one service (your backend at `host.docker.internal:8080`)
and a `/api` route. Within a few seconds the data plane has it.

Kong now listens on `:8000` and forwards `/api/*` to your backend on `:8080`.
Same calls, now through the gateway (note the `/api` prefix and port 8000):
```bash
curl -s localhost:8000/api/products | python3 -m json.tool
curl -s localhost:8000/api/inventory/SKU-1024 | python3 -m json.tool
```

**The point:** nothing about the backend changed. But now there is one place
every request passes through — the place where, in stage 5, we'll add auth,
limits, and logging without touching application code. This is the N+M control
point from the slides.

> If you see a connection error, Docker can't reach your host. Confirm the
> backend is still running and that Docker Desktop is started.

---

## Stage 3 — Let a model call the API

The backend and Kong stay running. The script sends its calls to Kong by default
(`API_BASE_URL=http://localhost:8000/api` in your `.env`).

```bash
python agent_demo.py
```

Watch the trace: the model decides to check inventory, your code runs the real
`GET /inventory/SKU-1024` through Kong, the result goes back, and the model
decides to place the order. The `[tool ]` and `[api ]` lines are the model
asking and your code acting.

Try editing the task at the bottom of `agent_demo.py` to order **SKU-2048**
(which is out of stock) and re-run. The model checks first, sees zero stock, and
declines to order — because the *API* told it so. The intelligence is in the
model; the truth is in the API.

**The point:** a model on its own only produces text. Every action it takes is an
API call underneath — and here, every one of those calls goes through the
gateway.

---

## Stage 4 

### 4a. Expose the API as an MCP server 

```bash
ksync kong.mcp.yaml
```

Test MCP connectivity and tools using Insomnia. Note that this MCP server is still unauthenticated

---

## Stage 5 — Governance

### 5.1 — Run Keycloak and provision the realm

```bash
docker compose -f keycloak/docker-compose.keycloak.yml up -d
./keycloak/setup-keycloak.sh
```
This creates the `mcp` realm, a confidential client `mcp-kong` (the OpenAI agent
uses it for a client-credentials token), a public client `mcp-inspector` (for
interactive login), and a `demo`/`demo` user. Issuer:
`http://host.docker.internal:8081/realms/mcp`.

### 5.2 — Drive it with OpenAI through Kong

```bash
python openai_mcp_agent.py
```
The script gets a Keycloak token, opens an MCP session to `http://localhost:8000/mcp`
with that bearer token, lists the tools Kong generated, and lets OpenAI call them
to answer the task. The model holds only a short-lived gateway token — never a
credential for the backend.

---

## Reset / teardown

```bash
# Stop the Konnect data plane:
docker compose down
# Stop Keycloak (stage 6):
docker compose -f keycloak/docker-compose.keycloak.yml down
# Optionally reset the control plane config (remove all synced entities):
#   deck gateway reset --konnect-token "$KONNECT_TOKEN" \
#     --konnect-control-plane-name "$KONNECT_CONTROL_PLANE"
# Stop the backend:    Ctrl-C in its terminal
# Order data is in-memory and resets when you restart the backend.
```

## Troubleshooting

- **Kong can't reach the backend** — the backend must be running on `:8080` and
  Docker Desktop must be started. The data plane maps `host.docker.internal` to
  your host automatically.
- **`401` after stage 5** — the governance config is still synced. Re-sync the
  routing-only state to drop auth: `ksync kong.yaml`.
- **`openai.AuthenticationError`** — your `OPENAI_API_KEY` in `.env` is missing or
  wrong.
- **tokens rejected (401 with a valid-looking token)** — the token's `iss`
  must equal the issuer Kong validates. Keep `127.0.0.1 host.docker.internal` in
  `/etc/hosts` and `KEYCLOAK_ISSUER=http://host.docker.internal:8081/realms/mcp`.
- **Data plane won't start / cert errors** — `konnect/tls.crt` and
  `konnect/tls.key` must contain the real PEM blocks from your Konnect data-plane
  node, and the `KONNECT_CP_*`/`KONNECT_TP_*` endpoints must match it.
- **Port already in use** — something else is on 8000/8443/8080. Stop it or
  change the ports in `docker-compose.yml` and the commands above.
