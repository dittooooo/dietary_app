from __future__ import annotations

import logging
from typing import Dict

from fastapi import APIRouter, FastAPI, Header, HTTPException, Query
from fastapi.responses import JSONResponse
from neo4j.exceptions import Neo4jError

from .agent import NutritionAgent
from .config import validate_required_config
from .models import (
    DishNutritionRequest, DishNutritionResponse, DishSearchResponse,
    NutritionAgentRequest, NutritionAgentResponse,
)


# 讓 FastAPI 回應明確帶上 UTF-8，避免繁體中文在呼叫端顯示亂碼。
class UTF8JSONResponse(JSONResponse):
    media_type = "application/json; charset=utf-8"


# 建立 FastAPI 應用程式。此檔案是外部呼叫者進入 Nutrition Agent 的 HTTP 入口。
app = FastAPI(
    title="Nutrition Agent GraphRAG API",
    default_response_class=UTF8JSONResponse,
)
api = APIRouter(prefix="/nutritionist-agent")
validate_required_config()
agent = NutritionAgent()
logging.basicConfig(level=logging.INFO, format="%(message)s", force=True)
logger = logging.getLogger("nutritionist.agent")


def trace(trace_id: str | None, state: str, message: str) -> None:
    logger.info("[%s] [NutritionistAgent] [%s] %s", (trace_id or "-")[:12], state, message)

# 提供最基本的服務存活檢查，不會連線 Neo4j 或 OpenAI。
@api.get("/health")
def health_check() -> Dict[str, str]:
    return {"status": "ok", "service": "nutrition_agent"}


# 確認服務已可處理請求，重點是檢查 Neo4j driver 是否能連線。
@api.get("/ready")
def readiness_check() -> Dict[str, str]:
    try:
        agent.retriever.driver.verify_connectivity()
    except Neo4jError as exc:
        raise HTTPException(status_code=503, detail=f"Neo4j connection failed: {exc}") from exc
    return {"status": "ready", "neo4j": "ok"}


# 依名稱關鍵字搜尋 Dish 與 FoodItem 節點，不呼叫 OpenAI 或營養計算流程。
@api.get("/dishes/search", response_model=DishSearchResponse)
def dish_search(
    q: str = Query(..., min_length=1, max_length=100),
    limit: int = Query(30, ge=1, le=50),
) -> DishSearchResponse:
    try:
        return agent.search_dishes(q, limit=limit)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Neo4jError as exc:
        raise HTTPException(status_code=503, detail=f"Neo4j query failed: {exc}") from exc


# 接收使用者問題與個人/飲食資料，交給 NutritionAgent 完成 GraphRAG 流程。
@api.post("/ask", response_model=NutritionAgentResponse)
def ask(
    req: NutritionAgentRequest,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> NutritionAgentResponse:
    dishes = [item.dish_name for item in req.dish_info_list]
    trace(x_trace_id, "STARTED", f"執行 GraphRAG 飲食建議，料理={dishes} question_type={req.question_type}")
    try:
        result = agent.ask(req)
        trace(x_trace_id, "COMPLETED", f"飲食建議完成，料理數={len(result.dish_advice)}")
        return result
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Neo4jError as exc:
        raise HTTPException(status_code=503, detail=f"Neo4j query failed: {exc}") from exc


# 查詢單一道料理的營養成分，提供飲食紀錄新增資料時使用，不呼叫 OpenAI。
@api.post("/dish-nutrition", response_model=DishNutritionResponse)
def dish_nutrition(
    req: DishNutritionRequest,
    x_trace_id: str | None = Header(default=None, alias="X-Trace-Id"),
) -> DishNutritionResponse:
    trace(x_trace_id, "STARTED", f"查詢單一料理營養：{req.dish_name[:50]}")
    try:
        # HTTP 層只負責接收 request 與轉換錯誤碼，實際圖譜檢索交給 NutritionAgent。
        result = agent.get_dish_nutrition(req)
        trace(x_trace_id, "COMPLETED", f"營養查詢完成 matched={result.dish_nutrition.matched_name}")
        return result
    except ValueError as exc:
        # 例如 dish_name 是空字串時回 400，表示呼叫端輸入不合法。
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        # 保留與 /ask 相同的錯誤語意：服務依賴或流程失敗時回 503。
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Neo4jError as exc:
        # Neo4j 查詢或連線失敗時回 503，呼叫端可稍後重試。
        raise HTTPException(status_code=503, detail=f"Neo4j query failed: {exc}") from exc


app.include_router(api)
