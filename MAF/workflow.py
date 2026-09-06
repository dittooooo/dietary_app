from __future__ import annotations

from typing import Any, Protocol

from agent_framework import Case, Default, Executor, WorkflowBuilder, WorkflowContext, handler
from typing_extensions import Never

from .trace import summarize, trace


class ConversationServices(Protocol):
    async def prepare(self, user_prompt: str, temp_story: list[dict[str, str]]) -> dict[str, Any]: ...

    async def call_dietary_agent(
        self, request_body: dict[str, Any], authorization: str | None
    ) -> dict[str, Any]: ...

    async def create_diet_records(
        self, records: list[dict[str, Any]], authorization: str | None
    ) -> dict[str, Any]: ...

    async def fetch_dish_nutrition(self, dish_name: str) -> dict[str, float]: ...

    async def call_companion_reply(
        self,
        context: dict[str, Any],
        dietary_agent_response: dict[str, Any] | None,
        dietary_agent_error: str | None,
    ) -> str: ...


class IntakeExecutor(Executor):
    def __init__(self, services: ConversationServices) -> None:
        super().__init__(id="intake")
        self.services = services

    @handler
    async def process(self, request: dict, ctx: WorkflowContext[dict]) -> None:
        trace("MAF", "INTAKE_STARTED", f"IntakeAgent 正在分析：{summarize(request['user_prompt'])}")
        prepared = await self.services.prepare(request["user_prompt"], request["temp_story"])
        prepared["authorization"] = request.get("authorization")
        screening = prepared.get("screening", {})
        intent = screening.get("intent_category") or "general_chat"
        dishes = [item.get("name") for item in screening.get("meal_items", []) if isinstance(item, dict)]
        trace("MAF", "ROUTED", f"分流完成 intent={intent} dishes={dishes or '無'}")
        await ctx.send_message(prepared)


def _response_payload(context: dict[str, Any], reply: str, error: str | None) -> dict[str, Any]:
    screening = context["screening"]
    return {
        "success": True,
        "companion_reply": reply,
        "intent_category": screening.get("intent_category") or "general_chat",
        "meal_items": screening.get("meal_items") or [],
        "query_date": screening.get("query_date"),
        "dietary_agent_error": error,
        # This is consumed by the HTTP layer for confirmation/resume state and
        # is removed before the response is returned to the client.
        "_workflow_context": context,
    }


class DirectReplyExecutor(Executor):
    def __init__(self, services: ConversationServices) -> None:
        super().__init__(id="direct_reply")
        self.services = services

    @handler
    async def process(self, context: dict, ctx: WorkflowContext[Never, dict]) -> None:
        trace("MAF", "AGENT_SELECTED", "輪到 CompanionAgent：產生一般對話的最終回覆")
        reply = await self.services.call_companion_reply(context, None, None)
        trace("MAF", "COMPLETED", "一般對話流程完成")
        await ctx.yield_output(_response_payload(context, reply, None))


class DietaryAdviceExecutor(Executor):
    def __init__(self, services: ConversationServices) -> None:
        super().__init__(id="dietary_advice")
        self.services = services

    @handler
    async def process(self, context: dict, ctx: WorkflowContext[Never, dict]) -> None:
        dietary_response: dict[str, Any] | None = None
        dietary_error: str | None = None
        try:
            trace("MAF", "AGENT_SELECTED", "輪到 DietaryAgent：整理個人資料並取得飲食建議")
            dietary_response = await self.services.call_dietary_agent(
                context["dietary_agent_request"], context.get("authorization")
            )
        except Exception as error:
            dietary_error = str(error)
            trace("MAF", "DOWNSTREAM_FAILED", f"DietaryAgent 失敗：{summarize(error)}")

        trace("MAF", "AGENT_SELECTED", "輪到 CompanionAgent：將處理結果轉成自然語言")
        reply = await self.services.call_companion_reply(context, dietary_response, dietary_error)
        trace("MAF", "COMPLETED", "飲食建議流程完成")
        await ctx.yield_output(_response_payload(context, reply, dietary_error))


def create_conversation_workflow(services: ConversationServices):
    intake = IntakeExecutor(services)
    direct_reply = DirectReplyExecutor(services)
    dietary_advice = DietaryAdviceExecutor(services)
    return (
        WorkflowBuilder(
            start_executor=intake,
            output_from=[direct_reply, dietary_advice],
        )
        .add_switch_case_edge_group(
            intake,
            [
                Case(
                    condition=lambda data: data.get("dietary_agent_request") is not None,
                    target=dietary_advice,
                ),
                Default(target=direct_reply),
            ],
        )
        .build()
    )
