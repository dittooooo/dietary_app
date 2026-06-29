from __future__ import annotations

from typing import Dict

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from neo4j.exceptions import Neo4jError

from .agent import NutritionAgent
from .config import validate_required_config
from .models import NutritionAgentRequest, NutritionAgentResponse


class UTF8JSONResponse(JSONResponse):
    media_type = "application/json; charset=utf-8"


app = FastAPI(
    title="Nutrition Agent GraphRAG API",
    default_response_class=UTF8JSONResponse,
)
validate_required_config()
agent = NutritionAgent()


@app.get("/health")
def health_check() -> Dict[str, str]:
    return {"status": "ok", "service": "nutrition_agent"}


@app.get("/ready")
def readiness_check() -> Dict[str, str]:
    try:
        agent.retriever.driver.verify_connectivity()
    except Neo4jError as exc:
        raise HTTPException(status_code=503, detail=f"Neo4j connection failed: {exc}") from exc
    return {"status": "ready", "neo4j": "ok"}


@app.post("/ask", response_model=NutritionAgentResponse)
def ask(req: NutritionAgentRequest) -> NutritionAgentResponse:
    try:
        return agent.ask(req)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Neo4jError as exc:
        raise HTTPException(status_code=503, detail=f"Neo4j query failed: {exc}") from exc
