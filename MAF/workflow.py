from __future__ import annotations

from typing import Any, Protocol

from agent_framework import Case, Default, Executor, WorkflowBuilder, WorkflowContext, handler
from typing_extensions import Never


class ConversationServices(Protocol):
    async def prepare(self, user_prompt: str, temp_story: list[dict[str, str]]) -> dict[str, Any]: ...

    async def call_dietary_agent(
        self, request_body: dict[str, Any], authorization: str | None
    ) -> dict[str, Any]: ...

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
        prepared = await self.services.prepare(request["user_prompt"], request["temp_story"])
        prepared["authorization"] = request.get("authorization")
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
    }


class DirectReplyExecutor(Executor):
    def __init__(self, services: ConversationServices) -> None:
        super().__init__(id="direct_reply")
        self.services = services

    @handler
    async def process(self, context: dict, ctx: WorkflowContext[Never, dict]) -> None:
        reply = await self.services.call_companion_reply(context, None, None)
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
            dietary_response = await self.services.call_dietary_agent(
                context["dietary_agent_request"], context.get("authorization")
            )
        except Exception as error:
            dietary_error = str(error)

        reply = await self.services.call_companion_reply(context, dietary_response, dietary_error)
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
