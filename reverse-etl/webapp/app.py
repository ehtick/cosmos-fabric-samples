# Customer 360 Semantic Search — FastAPI App
# Uses Cosmos DB's native VectorDistance() for server-side vector search.
#
# Run:
#   cd webapp
#   .venv\Scripts\activate
#   python app.py
#
# Then open http://localhost:8000 in your browser.

import os
import time
import traceback

from dotenv import load_dotenv
import openai
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

# Load .env file (if present) so you don't have to export vars manually
load_dotenv()

# ============================================================================
# Configuration  (loaded from .env — copy .env.example to .env to get started)
# ============================================================================

COSMOS_ENDPOINT = os.environ["COSMOS_ENDPOINT"]
DATABASE_NAME = os.environ["COSMOS_DATABASE"]
CONTAINER_NAME = os.environ["COSMOS_CONTAINER"]

AZURE_OPENAI_ENDPOINT = os.environ["AZURE_OPENAI_ENDPOINT"]
AZURE_OPENAI_KEY = os.environ["AZURE_OPENAI_KEY"]
OPENAI_MODEL = os.environ.get("OPENAI_EMBEDDING_MODEL", "text-embedding-ada-002")
OPENAI_API_VERSION = os.environ.get("OPENAI_API_VERSION", "2023-05-15")


# ============================================================================
# Singletons — create once, reuse across requests
# ============================================================================

class _FabricCosmosCredential:
    """Wraps DefaultAzureCredential to use the standard Cosmos DB scope.

    Fabric mirrored Cosmos DB endpoints (*.cosmos.fabric.microsoft.com) aren't
    registered as AAD resource principals, so the SDK's default scope (derived
    from the endpoint URL) fails.  This wrapper redirects token requests to
    the standard https://cosmos.azure.com/.default scope instead.
    """
    _COSMOS_SCOPE = "https://cosmos.azure.com/.default"

    def __init__(self):
        from azure.identity import DefaultAzureCredential
        self._inner = DefaultAzureCredential()

    def get_token(self, *scopes, **kwargs):
        return self._inner.get_token(self._COSMOS_SCOPE, **kwargs)

    # Newer azure-identity versions call get_token_info
    def get_token_info(self, *scopes, **kwargs):
        return self._inner.get_token_info(self._COSMOS_SCOPE, **kwargs)


def _create_cosmos_client():
    from azure.cosmos import CosmosClient
    return CosmosClient(COSMOS_ENDPOINT, credential=_FabricCosmosCredential())


cosmos_client = _create_cosmos_client()
cosmos_container = (
    cosmos_client.get_database_client(DATABASE_NAME)
                 .get_container_client(CONTAINER_NAME)
)

openai_client = openai.AzureOpenAI(
    azure_endpoint=AZURE_OPENAI_ENDPOINT,
    api_key=AZURE_OPENAI_KEY,
    api_version=OPENAI_API_VERSION,
)


# ============================================================================
# Helpers
# ============================================================================

def generate_embedding(text: str) -> list[float]:
    """Generate an embedding vector for the given text."""
    response = openai_client.embeddings.create(
        input=text.strip(),
        model=OPENAI_MODEL,
    )
    return response.data[0].embedding


def _extract_segment(query: str) -> str | None:
    """Detect a customer segment keyword in the search query."""
    q = query.lower()
    if "high value" in q or "high-value" in q:
        return "High Value"
    if "medium value" in q or "medium-value" in q:
        return "Medium Value"
    if "low value" in q or "low-value" in q:
        return "Low Value"
    return None


def vector_search(
    query_embedding: list[float],
    top_k: int = 10,
    segment_filter: str | None = None,
) -> list[dict]:
    """
    Perform vector search using Cosmos DB's native VectorDistance() function.
    Runs entirely server-side — no client-side similarity math needed.

    If *segment_filter* is provided (e.g. "High Value"), a WHERE clause limits
    results to that segment before ranking by vector similarity.
    """
    where_clause = ""
    parameters = [
        {"name": "@embedding", "value": query_embedding},
        {"name": "@topK", "value": top_k},
    ]

    if segment_filter:
        where_clause = "WHERE c.customer_segment = @segment"
        parameters.append({"name": "@segment", "value": segment_filter})

    query = f"""
    SELECT TOP @topK
        c.customer_id,
        c.customer_name,
        c.category,
        c.buying_group,
        c.postal_code,
        c.total_transactions,
        c.total_items_purchased,
        c.total_revenue,
        c.avg_transaction_value,
        c.unique_products_purchased,
        c.customer_segment,
        c.last_purchase_date,
        c.first_purchase_date,
        c.days_since_last_purchase,
        c.customer_lifetime_days,
        c.avg_days_between_purchases,
        VectorDistance(c.embedding, @embedding) AS similarity_score
    FROM c
    {where_clause}
    ORDER BY VectorDistance(c.embedding, @embedding)
    """

    return list(
        cosmos_container.query_items(
            query=query,
            parameters=parameters,
            enable_cross_partition_query=True,
        )
    )


# ============================================================================
# FastAPI App
# ============================================================================

app = FastAPI(title="Customer 360 Semantic Search API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class SearchRequest(BaseModel):
    query: str
    topK: int = 10


@app.get("/")
def index():
    """Serve the frontend HTML."""
    return FileResponse("static/index.html")


@app.post("/api/search")
def search(body: SearchRequest):
    """Semantic search endpoint."""
    try:
        t0 = time.perf_counter()
        segment = _extract_segment(body.query)
        label = f" [segment={segment}]" if segment else ""
        print(f"Searching: {body.query} (top_k={body.topK}){label}", flush=True)
        query_embedding = generate_embedding(body.query)
        results = vector_search(query_embedding, body.topK, segment_filter=segment)
        elapsed_ms = round((time.perf_counter() - t0) * 1000)
        print(f"  OK — {len(results)} results in {elapsed_ms}ms", flush=True)
        return {"results": results, "elapsed_ms": elapsed_ms}
    except Exception as e:
        tb = traceback.format_exc()
        print(f"  ERROR: {e}\n{tb}", flush=True)
        return JSONResponse(status_code=500, content={"error": str(e), "traceback": tb})


@app.get("/api/config")
def config():
    """Return non-secret config for the diagnostics panel."""
    return {"cosmos_endpoint": COSMOS_ENDPOINT}


@app.get("/api/health")
def health():
    """Health check endpoint."""
    return {"status": "healthy"}


@app.get("/api/test-vector")
def test_vector():
    """Diagnostic: test VectorDistance from a request handler."""
    try:
        emb = generate_embedding("test query")
        results = vector_search(emb, 3)
        return {"count": len(results), "results": results}
    except Exception as e:
        tb = traceback.format_exc()
        print(f"  TEST-VECTOR ERROR: {e}\n{tb}", flush=True)
        return JSONResponse(status_code=500, content={"error": str(e), "traceback": tb})


# Serve static files (CSS, JS, images) — must come AFTER API routes
app.mount("/static", StaticFiles(directory="static"), name="static")


# ============================================================================
# Entry point
# ============================================================================

if __name__ == "__main__":
    print("=" * 60)
    print("Customer 360 Semantic Search API  (FastAPI + Uvicorn)")
    print("  Uses Cosmos DB VectorDistance() for server-side search")
    print("=" * 60)
    print("Endpoints:")
    print("  GET  /              - Frontend UI")
    print("  POST /api/search    - Vector search via VectorDistance()")
    print("  GET  /api/health    - Health check")
    print()
    print("Configuration:")
    print(f"  COSMOS_ENDPOINT          = {COSMOS_ENDPOINT[:50]}...")
    print(f"  COSMOS_DATABASE          = {DATABASE_NAME}")
    print(f"  COSMOS_CONTAINER         = {CONTAINER_NAME}")
    print(f"  AZURE_OPENAI_ENDPOINT    = {AZURE_OPENAI_ENDPOINT or '(not set)'}")
    print(f"  OPENAI_EMBEDDING_MODEL   = {OPENAI_MODEL}")
    print("=" * 60)
    uvicorn.run(app, host="127.0.0.1", port=8000)
