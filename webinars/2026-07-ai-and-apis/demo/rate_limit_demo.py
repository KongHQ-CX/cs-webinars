"""
STAGE 6 — show the rate limit enforced on the MCP proxy.

Sends more MCP requests than the per-minute ceiling and prints the HTTP status
of each. Kong returns 429 once the limit is crossed — the agent loop is capped
at the gateway, not in the backend.

Run:  python rate_limit_demo.py
Env (.env): KEYCLOAK_ISSUER, KC_CLIENT_ID, KC_CLIENT_SECRET, MCP_URL,
            RATE_LIMIT_PER_MIN
"""
import os
import requests
from dotenv import load_dotenv

load_dotenv()

ISSUER = os.environ["KEYCLOAK_ISSUER"].rstrip("/")
TOKEN_URL = os.environ.get("KC_TOKEN_URL", f"{ISSUER}/protocol/openid-connect/token")
CLIENT_ID = os.environ.get("KC_CLIENT_ID", "mcp-kong")
CLIENT_SECRET = os.environ.get("KC_CLIENT_SECRET", "mcp-kong-secret")
MCP_URL = os.environ.get("MCP_URL", "http://localhost:8000/mcp")
LIMIT = int(os.environ.get("RATE_LIMIT_PER_MIN", "10"))


def get_token():
    r = requests.post(TOKEN_URL, data={
        "grant_type": "client_credentials",
        "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET}, timeout=15)
    r.raise_for_status()
    return r.json()["access_token"]


def main():
    token = get_token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/list"}

    n = LIMIT + 3
    print(f"Firing {n} MCP requests at a {LIMIT}/min limit...\n")
    for i in range(1, n + 1):
        r = requests.post(MCP_URL, headers=headers, json=body, timeout=15)
        note = "  <- blocked by Kong" if r.status_code == 429 else ""
        remaining = r.headers.get("RateLimit-Remaining") or r.headers.get("X-RateLimit-Remaining-Minute", "")
        print(f"  request {i:>2}: HTTP {r.status_code}"
              f"{f'  (remaining {remaining})' if remaining else ''}{note}")

    print("\nWithout a valid token you never get this far — try removing the "
          "Authorization header and you'll see 401 from the openid-connect plugin.")


if __name__ == "__main__":
    main()
