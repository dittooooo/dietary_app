from __future__ import annotations

from typing import Dict

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from neo4j.exceptions import Neo4jError

from .agent import NutritionAgent
from .config import validate_required_config
from .models import NutritionAgentRequest, NutritionAgentResponse


# 讓 FastAPI 回應明確帶上 UTF-8，避免繁體中文在呼叫端顯示亂碼。
class UTF8JSONResponse(JSONResponse):
    media_type = "application/json; charset=utf-8"


# 建立 FastAPI 應用程式。此檔案是外部呼叫者進入 Nutrition Agent 的 HTTP 入口。
app = FastAPI(
    title="Nutrition Agent GraphRAG API",
    default_response_class=UTF8JSONResponse,
)
validate_required_config()
agent = NutritionAgent()

# 提供最基本的服務存活檢查，不會連線 Neo4j 或 OpenAI。
@app.get("/health")
def health_check() -> Dict[str, str]:
    return {"status": "ok", "service": "nutrition_agent"}


# 確認服務已可處理請求，重點是檢查 Neo4j driver 是否能連線。
@app.get("/ready")
def readiness_check() -> Dict[str, str]:
    try:
        agent.retriever.driver.verify_connectivity()
    except Neo4jError as exc:
        raise HTTPException(status_code=503, detail=f"Neo4j connection failed: {exc}") from exc
    return {"status": "ready", "neo4j": "ok"}


# 接收使用者問題與個人/飲食資料，交給 NutritionAgent 完成 GraphRAG 流程。
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
