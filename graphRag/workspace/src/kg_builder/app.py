from __future__ import annotations

import os
from typing import Any, Dict, List

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel

try:
    from .query_engine import QueryEngine
except ImportError:
    from query_engine import QueryEngine


NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")

class UTF8JSONResponse(JSONResponse):
    media_type = "application/json; charset=utf-8"


app = FastAPI(
    title="Diet Text-to-Cypher GraphRAG",
    default_response_class=UTF8JSONResponse,
)
engine = QueryEngine(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)


class AskRequest(BaseModel):
    question: str


class AskResponse(BaseModel):
    question: str
    cypher: str
    cypher_rationale: str
    graph_rows: List[Dict[str, Any]]
    answer: str


class RecommendRequest(BaseModel):
    dish_name: str
    disease_name: str


class RecommendResponse(BaseModel):
    dish: str
    disease: str
    question: str
    cypher: str
    graph_rows: List[Dict]
    advice: str


@app.get("/health")
def health_check() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/ask", response_model=AskResponse)
def ask(req: AskRequest) -> Dict[str, Any]:
    return engine.ask(req.question)


@app.post("/recommend", response_model=RecommendResponse)
def recommend(req: RecommendRequest) -> Dict[str, Any]:
    return engine.generate_recommendation(req.dish_name, req.disease_name)
