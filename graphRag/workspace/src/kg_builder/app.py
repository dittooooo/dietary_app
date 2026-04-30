from __future__ import annotations

import os
from typing import Dict, List

from fastapi import FastAPI
from pydantic import BaseModel

from query_engine import QueryEngine


NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")

app = FastAPI(title="Diet GraphRAG MVP")
engine = QueryEngine(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)


class RecommendRequest(BaseModel):
    dish_name: str
    disease_name: str


class RecommendResponse(BaseModel):
    dish: str
    disease: str
    graph_rows: List[Dict]
    advice: str


@app.get("/health")
def health_check() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/recommend", response_model=RecommendResponse)
def recommend(req: RecommendRequest) -> Dict:
    return engine.generate_recommendation(req.dish_name, req.disease_name)