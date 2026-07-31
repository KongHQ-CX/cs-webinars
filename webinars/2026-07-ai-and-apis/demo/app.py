"""
Inventory & Orders — the one backend service for the whole demo.

This never changes across the five stages. Only the connectivity in front of it
changes. Run it directly with:

    uvicorn app:app --reload --port 8080

Endpoints:
    GET  /health              -> liveness check
    GET  /products            -> list all products
    GET  /products/{sku}      -> one product
    GET  /inventory/{sku}     -> stock level for a SKU
    POST /orders              -> place an order {sku, quantity}
"""
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from datetime import datetime, timezone
import uuid

app = FastAPI(
    title="Inventory & Orders",
    version="1.0.0",
    # Upstream URL the Kong (Konnect) data-plane container uses to reach this
    # service on your Mac. openapi2mcp reads it when generating the MCP config.
    servers=[{"url": "http://host.docker.internal:8080"}],
)

# --- In-memory data. Resets on restart, which is fine for a demo. ---
PRODUCTS = {
    "SKU-1024": {"sku": "SKU-1024", "name": "Aeron Standing Desk", "price": 689.00, "stock": 12},
    "SKU-2048": {"sku": "SKU-2048", "name": "Mesh Task Chair", "price": 245.00, "stock": 0},
    "SKU-3072": {"sku": "SKU-3072", "name": "27-inch 4K Monitor", "price": 399.00, "stock": 5},
    "SKU-4096": {"sku": "SKU-4096", "name": "Mechanical Keyboard", "price": 119.00, "stock": 40},
    "SKU-5120": {"sku": "SKU-5120", "name": "USB-C Dock", "price": 199.00, "stock": 3},
}
ORDERS = {}


class OrderRequest(BaseModel):
    sku: str = Field(..., examples=["SKU-1024"])
    quantity: int = Field(..., gt=0, examples=[1])


@app.get("/health", operation_id="health", summary="Liveness check")
def health():
    return {"status": "ok"}


@app.get("/products", operation_id="list_products", summary="List all products with price and stock")
def list_products():
    return {"products": list(PRODUCTS.values())}


@app.get("/products/{sku}", operation_id="get_product", summary="Get one product by SKU")
def get_product(sku: str):
    product = PRODUCTS.get(sku.upper())
    if not product:
        raise HTTPException(status_code=404, detail=f"Unknown SKU: {sku}")
    return product


@app.get("/inventory/{sku}", operation_id="get_inventory", summary="Get the stock level for a SKU")
def get_inventory(sku: str):
    product = PRODUCTS.get(sku.upper())
    if not product:
        raise HTTPException(status_code=404, detail=f"Unknown SKU: {sku}")
    return {"sku": product["sku"], "name": product["name"], "stock": product["stock"]}


@app.post("/orders", operation_id="place_order", summary="Place an order for a quantity of a SKU")
def place_order(order: OrderRequest):
    product = PRODUCTS.get(order.sku.upper())
    if not product:
        raise HTTPException(status_code=404, detail=f"Unknown SKU: {order.sku}")
    if product["stock"] < order.quantity:
        raise HTTPException(
            status_code=409,
            detail=f"Insufficient stock for {product['sku']}: "
                   f"requested {order.quantity}, available {product['stock']}",
        )
    product["stock"] -= order.quantity
    order_id = f"ORD-{uuid.uuid4().hex[:8].upper()}"
    record = {
        "order_id": order_id,
        "sku": product["sku"],
        "name": product["name"],
        "quantity": order.quantity,
        "unit_price": product["price"],
        "total": round(product["price"] * order.quantity, 2),
        "placed_at": datetime.now(timezone.utc).isoformat(),
        "remaining_stock": product["stock"],
    }
    ORDERS[order_id] = record
    return record
