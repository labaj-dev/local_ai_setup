"""
Tiny bridge server so Continue's @HTTP context provider can pull results
from a local SearXNG instance.

Run:
    pip install fastapi uvicorn requests
    python3 searxng_bridge.py

Continue will POST {"query": "...", ...} to this server; it forwards the
query to SearXNG's JSON API and returns results in the shape Continue expects:
[{"name": ..., "description": ..., "content": ...}, ...]
"""

from fastapi import FastAPI, Request
import requests

app = FastAPI()

SEARXNG_URL = "http://localhost:8080/search"
MAX_RESULTS = 5

import re

@app.post("/context-provider")
async def context_provider(request: Request):
    body = await request.json()
    query = (body.get("query") or "").strip()

    if not query:
        full_input = (body.get("fullInput") or "").strip()
        # Strip a leading "@Web Search" (or similar) mention token, if present
        query = re.sub(r"^@\S+(\s+\S+)?\s*", "", full_input).strip()
        if not query:
            query = full_input

    if not query:
        return [{
            "name": "Web Search",
            "description": "No query provided",
            "content": "No search query was found in your message.",
        }]

    resp = requests.get(
        SEARXNG_URL,
        params={"q": query, "format": "json"},
        timeout=10,
    )
    resp.raise_for_status()
    results = resp.json().get("results", [])[:MAX_RESULTS]

    return [
        {
            "name": r.get("title", r.get("url", "result")),
            "description": r.get("url", ""),
            "content": f"{r.get('title', '')}\n{r.get('url', '')}\n{r.get('content', '')}",
        }
        for r in results
    ]

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8765)
