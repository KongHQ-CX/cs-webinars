"""
STAGE 3 — Models talk. APIs act. (OpenAI edition.)

A model only produces text. To *do* something it emits a tool call; your code
runs the real API request through Kong and returns the result. This gives OpenAI
two tools — check inventory and place an order — and lets it work a task end to
end. Every action underneath is an HTTP call to the same backend via Kong.

Run:  python agent_demo.py
Env (.env): OPENAI_API_KEY, OPENAI_MODEL, API_BASE_URL, API_KEY (optional)
"""
import os
import json
import requests
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

API_BASE_URL = os.environ.get("API_BASE_URL", "http://localhost:8000/api")
API_KEY = os.environ.get("API_KEY", "")
MODEL = os.environ.get("OPENAI_MODEL", "gpt-4o")
client = OpenAI()


def _headers():
    return {"apikey": API_KEY} if API_KEY else {}


def get_inventory(sku: str) -> dict:
    r = requests.get(f"{API_BASE_URL}/inventory/{sku}", headers=_headers(), timeout=10)
    return {"status": r.status_code, "body": r.json() if r.content else None}


def place_order(sku: str, quantity: int) -> dict:
    r = requests.post(f"{API_BASE_URL}/orders", headers=_headers(),
                      json={"sku": sku, "quantity": quantity}, timeout=10)
    return {"status": r.status_code, "body": r.json() if r.content else None}


TOOLS = [
    {"type": "function", "function": {
        "name": "get_inventory",
        "description": "Check the current stock level for a product SKU.",
        "parameters": {"type": "object",
                       "properties": {"sku": {"type": "string", "description": "e.g. SKU-1024"}},
                       "required": ["sku"]}}},
    {"type": "function", "function": {
        "name": "place_order",
        "description": "Place an order for a quantity of a product SKU.",
        "parameters": {"type": "object",
                       "properties": {"sku": {"type": "string"},
                                      "quantity": {"type": "integer", "minimum": 1}},
                       "required": ["sku", "quantity"]}}},
]
DISPATCH = {"get_inventory": get_inventory, "place_order": place_order}


def run(task: str):
    print(f"\n=== TASK ===\n{task}\n")
    messages = [{"role": "user", "content": task}]
    while True:
        resp = client.chat.completions.create(
            model=MODEL, messages=messages, tools=TOOLS, tool_choice="auto")
        msg = resp.choices[0].message
        messages.append(msg.model_dump(exclude_none=True))
        if not msg.tool_calls:
            print(f"[model] {msg.content}")
            break
        for call in msg.tool_calls:
            args = json.loads(call.function.arguments or "{}")
            print(f"[tool ] {call.function.name}({json.dumps(args)})")
            result = DISPATCH[call.function.name](**args)
            print(f"[api  ] -> {json.dumps(result)}")
            messages.append({"role": "tool", "tool_call_id": call.id,
                             "content": json.dumps(result)})
    print("\n=== DONE ===")


if __name__ == "__main__":
    run("I need one standing desk, SKU-1024. Check it's in stock first, and if it "
        "is, place the order and tell me the order ID and total.")
