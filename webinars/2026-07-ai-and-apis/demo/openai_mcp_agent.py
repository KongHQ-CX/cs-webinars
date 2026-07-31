"""
STAGE 6 — OpenAI agent over Kong's OAuth-protected MCP server.

The flow this demonstrates end to end:
  1. Get an OAuth token from Keycloak (client-credentials grant).
  2. Open an MCP session to Kong's generated /mcp endpoint, sending that token.
     Kong's openid-connect plugin validates it before any tool is reachable.
  3. List the MCP tools Kong generated from the API, hand them to OpenAI.
  4. Let OpenAI pick tools; execute each call back through Kong over MCP.

No custom MCP server, and the model never sees a credential for the API — it
only ever holds a short-lived OAuth token for the gateway.

Run:  python openai_mcp_agent.py
Env (.env): OPENAI_API_KEY, OPENAI_MODEL, KEYCLOAK_ISSUER, KC_CLIENT_ID,
            KC_CLIENT_SECRET, MCP_URL
"""
import os
import json
import asyncio
import requests
from dotenv import load_dotenv
from openai import OpenAI
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

load_dotenv()

ISSUER = os.environ["KEYCLOAK_ISSUER"].rstrip("/")
TOKEN_URL = os.environ.get("KC_TOKEN_URL", f"{ISSUER}/protocol/openid-connect/token")
CLIENT_ID = os.environ.get("KC_CLIENT_ID", "mcp-kong")
CLIENT_SECRET = os.environ.get("KC_CLIENT_SECRET", "mcp-kong-secret")
MCP_URL = os.environ.get("MCP_URL", "http://localhost:8000/mcp")
MODEL = os.environ.get("OPENAI_MODEL", "gpt-4o")

openai = OpenAI()


def get_token() -> str:
    """Client-credentials grant from Keycloak."""
    r = requests.post(
        TOKEN_URL,
        data={"grant_type": "client_credentials",
              "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET},
        timeout=15,
    )
    r.raise_for_status()
    print(f"[oauth] got token from {TOKEN_URL}")
    return r.json()["access_token"]


def to_openai_tools(mcp_tools):
    """Map MCP tool definitions to OpenAI function-tool schema."""
    out = []
    for t in mcp_tools:
        out.append({
            "type": "function",
            "function": {
                "name": t.name,
                "description": t.description or t.name,
                "parameters": t.inputSchema or {"type": "object", "properties": {}},
            },
        })
    return out


async def run(task: str):
    token = get_token()
    headers = {"Authorization": f"Bearer {token}"}

    async with streamablehttp_client(MCP_URL, headers=headers) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = (await session.list_tools()).tools
            print(f"[mcp ] Kong exposed {len(tools)} tools: "
                  f"{', '.join(t.name for t in tools)}")
            oa_tools = to_openai_tools(tools)

            messages = [
                {"role": "system", "content": "You use the provided tools to answer. "
                                              "Call tools rather than guessing."},
                {"role": "user", "content": task},
            ]
            print(f"\n=== TASK ===\n{task}\n")

            while True:
                resp = openai.chat.completions.create(
                    model=MODEL, messages=messages, tools=oa_tools, tool_choice="auto",
                )
                msg = resp.choices[0].message
                messages.append(msg.model_dump(exclude_none=True))

                if not msg.tool_calls:
                    print(f"[model] {msg.content}")
                    break

                for call in msg.tool_calls:
                    args = json.loads(call.function.arguments or "{}")
                    print(f"[tool ] {call.function.name}({json.dumps(args)})")
                    result = await session.call_tool(call.function.name, args)
                    text = "".join(
                        c.text for c in result.content if getattr(c, "type", "") == "text"
                    ) or "(no text content)"
                    print(f"[mcp  ] -> {text[:200]}")
                    messages.append({
                        "role": "tool", "tool_call_id": call.id, "content": text,
                    })

            print("\n=== DONE ===")


if __name__ == "__main__":
    asyncio.run(run(
        "List the products, then tell me how many of the standing desk (SKU-1024) "
        "are in stock."
    ))
