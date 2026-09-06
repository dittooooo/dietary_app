from __future__ import annotations

import asyncio
import copy
import logging
import uuid
from datetime import date
from typing import Any

from fastapi import FastAPI, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from .clients import OpenAIServiceError, WorkflowServices, sanitize_temp_story
from .config import Settings
from .workflow import ConversationServices, create_conversation_workflow
from .trace import TRACE_HEADER, reset_trace_id, set_trace_id, summarize, trace, trace_payload


class ConversationRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    user_prompt: Any = None
    temp_story: list[dict[str, Any]] = Field(default_factory=list)
    session_id: str | None = None


class ConfirmationRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    confirmation_id: str
    meal_items: list[dict[str, Any]] = Field(default_factory=list)
    session_id: str | None = None


def _today_in_taipei() -> str:
    return date.today().isoformat()


def _meal_type(period: Any) -> tuple[str, str]:
    normalized = str(period or "其他").strip()
    if normalized == "早餐":
        return "BREAKFAST", ""
    if normalized in {"午餐", "中餐"}:
        return "LUNCH", ""
    if normalized == "晚餐":
        return "DINNER", ""
    return "DINNER", "[MealType:OTHER]"


def _record_payload(meal_items: list[dict[str, Any]], default_date: str) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for item in meal_items:
        name = str(item.get("name") or item.get("dish_name") or "").strip()
        if not name:
            continue
        try:
            quantity = int(float(item.get("quantity", item.get("amount", 1))))
        except (TypeError, ValueError):
            quantity = 1
        quantity = max(quantity, 1)
        meal_type, other_prefix = _meal_type(item.get("meal_period", item.get("meal_type")))
        record_date = str(item.get("record_date") or item.get("date") or default_date)
        records.append(
            {
                "dish_name": name,
                "amount": quantity,
                "meal_type": meal_type,
                "record_date": record_date,
                "description": f"{other_prefix}由 MAF Workflow 經使用者確認".strip(),
            }
        )
    return records


def create_app(services: ConversationServices | None = None) -> FastAPI:
    app = FastAPI(title="MAF Conversation Workflow", version="1.0.0")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.state.services = services
    pending: dict[str, dict[str, Any]] = {}
    completed: dict[str, dict[str, Any]] = {}
    pending_lock = asyncio.Lock()

    @app.middleware("http")
    async def workflow_trace(request, call_next):
        if request.url.path == "/health":
            return await call_next(request)
        run_id = (request.headers.get(TRACE_HEADER) or uuid.uuid4().hex)[:12]
        token = set_trace_id(run_id)
        trace("MAF", "HTTP_RECEIVED", f"{request.method} {request.url.path}")
        try:
            response = await call_next(request)
            response.headers[TRACE_HEADER] = run_id
            trace("MAF", "HTTP_COMPLETED", f"{request.method} {request.url.path} HTTP {response.status_code}")
            return response
        except Exception as error:
            trace("MAF", "HTTP_FAILED", summarize(error), level=logging.ERROR)
            raise
        finally:
            reset_trace_id(token)

    def get_services() -> ConversationServices:
        current_services = app.state.services
        if current_services is None:
            current_services = WorkflowServices(Settings.from_env())
            app.state.services = current_services
        return current_services

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/maf/ask", response_model=None)
    async def maf_ask(
        request: ConversationRequest,
        authorization: str | None = Header(default=None),
    ) -> Any:
        user_prompt = request.user_prompt.strip() if isinstance(request.user_prompt, str) else ""
        if not user_prompt:
            return JSONResponse(
                status_code=400,
                content={
                    "success": False,
                    "error_code": "BAD_REQUEST",
                    "error_message": "The 'user_prompt' field is required and must be a non-empty string.",
                },
            )

        trace("MAF", "RECEIVED", f"收到前端問題：{summarize(user_prompt)}")
        trace_payload("Frontend", "INPUT", "request", {
            "user_prompt": user_prompt,
            "temp_story": sanitize_temp_story(request.temp_story),
            "session_id": request.session_id,
        })
        try:
            current_services = get_services()
            workflow = create_conversation_workflow(current_services)
            result = await workflow.run(
                {
                    "user_prompt": user_prompt,
                    "temp_story": sanitize_temp_story(request.temp_story),
                    "authorization": authorization,
                    "session_id": request.session_id,
                }
            )
            output = dict(result.get_outputs()[0])
            context = output.pop("_workflow_context", None)
            if not isinstance(context, dict):
                raise RuntimeError("MAF workflow did not return its context.")

            if output.get("intent_category") == "meal_record" and output.get("meal_items"):
                confirmation_id = uuid.uuid4().hex
                async with pending_lock:
                    pending[confirmation_id] = {
                        "context": context,
                        "session_id": request.session_id,
                        "state": "WAITING_CONFIRMATION",
                    }
                output.update(
                    {
                        "status": "WAITING_CONFIRMATION",
                        "confirmation_id": confirmation_id,
                    }
                )
                trace("MAF", "WAITING_CONFIRMATION", f"草稿送回前端 confirmation_id={confirmation_id[:12]}")
            else:
                output["status"] = "COMPLETED"
            trace_payload("MAF", "OUTPUT", "frontend_response", output)
            return output
        except OpenAIServiceError as error:
            trace("MAF", "INTAKE_FAILED", f"OpenAI 呼叫失敗：{summarize(error)}", level=logging.ERROR)
            return JSONResponse(
                status_code=502,
                content={
                    "success": False,
                    "error_code": "OPENAI_SERVICE_ERROR",
                    "error_message": "Failed to communicate with OpenAI API. Please try again later.",
                    "debug_message": str(error),
                },
            )
        except Exception as error:
            trace("MAF", "FAILED", f"未預期錯誤：{summarize(error)}", level=logging.ERROR)
            return JSONResponse(
                status_code=500,
                content={
                    "success": False,
                    "error_code": "INTERNAL_SERVER_ERROR",
                    "error_message": "An unexpected error occurred on the server.",
                },
            )

    @app.post("/maf/confirm", response_model=None)
    async def maf_confirm(
        request: ConfirmationRequest,
        authorization: str | None = Header(default=None),
    ) -> Any:
        trace("MAF", "CONFIRMED", f"收到前端確認，共 {len(request.meal_items)} 筆飲食項目")
        async with pending_lock:
            if request.confirmation_id in completed:
                return completed[request.confirmation_id]
            entry = pending.get(request.confirmation_id)
            if entry is None:
                return JSONResponse(
                    status_code=404,
                    content={
                        "success": False,
                        "error_code": "CONFIRMATION_NOT_FOUND",
                        "error_message": "The confirmation request is no longer available.",
                    },
                )
            if entry["state"] == "PROCESSING":
                return JSONResponse(
                    status_code=409,
                    content={
                        "success": False,
                        "error_code": "CONFIRMATION_IN_PROGRESS",
                        "error_message": "The confirmation request is already being processed.",
                    },
                )
            entry["state"] = "PROCESSING"

        context = copy.deepcopy(entry["context"])
        default_date = context.get("screening", {}).get("query_date") or _today_in_taipei()
        records = _record_payload(request.meal_items, default_date)
        if not records:
            async with pending_lock:
                pending[request.confirmation_id]["state"] = "WAITING_CONFIRMATION"
            return JSONResponse(
                status_code=400,
                content={
                    "success": False,
                    "error_code": "INVALID_CONFIRMATION",
                    "error_message": "至少需要一筆有效的飲食紀錄。",
                },
            )

        try:
            current_services = get_services()
            trace("MAF", "DOWNSTREAM_PROCESSING", "補齊營養資料並寫入飲食紀錄")
            for record in records:
                try:
                    nutrition = await current_services.fetch_dish_nutrition(record["dish_name"])
                except Exception:
                    nutrition = {}
                amount = record["amount"]
                for key, value in nutrition.items():
                    record[key] = value * amount
            downstream = await current_services.create_diet_records(records, authorization)
            context["screening"]["meal_items"] = request.meal_items
            reply = await current_services.call_companion_reply(context, downstream, None)
            response = {
                "success": True,
                "status": "COMPLETED",
                "companion_reply": reply,
                "intent_category": "meal_record",
                "meal_items": request.meal_items,
                "query_date": context["screening"].get("query_date"),
                "confirmation_id": request.confirmation_id,
                "downstream_response": downstream,
            }
        except Exception as error:
            trace("MAF", "DOWNSTREAM_API_FAILED", f"確認流程失敗：{summarize(error)}", level=logging.ERROR)
            async with pending_lock:
                pending[request.confirmation_id]["state"] = "WAITING_CONFIRMATION"
            return JSONResponse(
                status_code=502,
                content={
                    "success": False,
                    "error_code": "DOWNSTREAM_API_FAILED",
                    "error_message": "儲存飲食紀錄或產生回覆時發生錯誤，請稍後再試。",
                    "debug_message": str(error),
                },
            )

        async with pending_lock:
            pending.pop(request.confirmation_id, None)
            completed[request.confirmation_id] = response
        trace("MAF", "COMPLETED", "飲食紀錄確認流程完成")
        return response

    return app


app = create_app()
