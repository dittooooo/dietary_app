from __future__ import annotations

from typing import Dict

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from .agent import NutritionAgent
from .models import NutritionAgentRequest, NutritionAgentResponse


class UTF8JSONResponse(JSONResponse):
    media_type = "application/json; charset=utf-8"


app = FastAPI(
    title="Nutrition Agent GraphRAG API",
    default_response_class=UTF8JSONResponse,
)
agent = NutritionAgent()


@app.get("/health")
def health_check() -> Dict[str, str]:
    return {"status": "ok", "service": "nutrition_agent"}


@app.post("/ask", response_model=NutritionAgentResponse)
def ask(req: NutritionAgentRequest) -> NutritionAgentResponse:
    try:
        return agent.ask(req)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
