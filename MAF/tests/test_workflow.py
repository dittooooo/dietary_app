from __future__ import annotations

import asyncio
from typing import Any

import pytest
from fastapi.testclient import TestClient

from MAF.app import create_app
from MAF.clients import build_dietary_agent_request, sanitize_screening, sanitize_temp_story
from MAF.workflow import create_conversation_workflow


class FakeServices:
    def __init__(self, intent: str) -> None:
        self.intent = intent
        self.dietary_calls: list[dict[str, Any]] = []
        self.companion_calls: list[dict[str, Any]] = []

    async def prepare(self, user_prompt: str, temp_story: list[dict[str, str]]) -> dict[str, Any]:
        meal_items = []
        question_type = "not_applicable"
        request = None
        if self.intent == "meal_record":
            meal_items = [{"name": "茶葉蛋", "quantity": 1, "unit": "顆", "meal_period": "早餐"}]
        elif self.intent == "dish_advice":
            meal_items = [{"name": "牛肉麵", "quantity": 1, "unit": "碗", "meal_period": "晚餐"}]
            question_type = "single_dish"
            request = {
                "question": user_prompt,
                "question_type": question_type,
                "dish_info_list": [{"dish_name": "牛肉麵", "amount": 1}],
            }
        return {
            "user_prompt": user_prompt,
            "temp_story": temp_story,
            "screening": {
                "should_handle": self.intent != "general_chat",
                "intent_category": self.intent,
                "question_type": question_type,
                "meal_items": meal_items,
                "query_date": None,
            },
            "emotion": {"primary_emotion": "neutral"},
            "dietary_agent_request": request,
        }

    async def call_dietary_agent(
        self, request_body: dict[str, Any], authorization: str | None
    ) -> dict[str, Any]:
        self.dietary_calls.append({"body": request_body, "authorization": authorization})
        return {"conclusion": "可以適量食用"}

    async def call_companion_reply(
        self,
        context: dict[str, Any],
        dietary_agent_response: dict[str, Any] | None,
        dietary_agent_error: str | None,
    ) -> str:
        self.companion_calls.append(
            {"context": context, "response": dietary_agent_response, "error": dietary_agent_error}
        )
        return f"reply:{context['screening']['intent_category']}"


@pytest.mark.parametrize(
    ("intent", "expected_dietary_calls"),
    [("general_chat", 0), ("meal_record", 0), ("dish_advice", 1)],
)
def test_three_conversation_routes(intent: str, expected_dietary_calls: int) -> None:
    asyncio.run(_assert_conversation_route(intent, expected_dietary_calls))


async def _assert_conversation_route(intent: str, expected_dietary_calls: int) -> None:
    services = FakeServices(intent)
    workflow = create_conversation_workflow(services)
    result = await workflow.run(
        {"user_prompt": "test", "temp_story": [], "authorization": "Bearer token"}
    )

    output = result.get_outputs()[0]
    assert output["intent_category"] == intent
    assert output["companion_reply"] == f"reply:{intent}"
    assert len(services.dietary_calls) == expected_dietary_calls
    assert len(services.companion_calls) == 1


def test_existing_screening_contract_is_preserved() -> None:
    screening = sanitize_screening(
        {
            "should_handle": True,
            "intent_category": "dish_advice",
            "question_type": "single_dish",
            "confidence": 0.9,
            "meal_items": [
                {"name": "牛肉麵", "quantity": 2, "unit": "碗", "meal_period": "晚餐"}
            ],
        }
    )
    request = build_dietary_agent_request(screening, "牛肉麵適合嗎？")

    assert screening["dish_info_list"] == {"牛肉麵": 2}
    assert request == {
        "question": "牛肉麵適合嗎？",
        "question_type": "single_dish",
        "dish_info_list": [{"dish_name": "牛肉麵", "amount": 2}],
    }


def test_temp_story_matches_existing_companion_limits() -> None:
    story = [
        {"role": "system", "content": "ignored"},
        {"role": "user", "content": "a" * 400},
        {"role": "assistant", "content": "b"},
        {"role": "user", "content": "c"},
        {"role": "assistant", "content": "d"},
    ]
    sanitized = sanitize_temp_story(story)
    assert len(sanitized) == 3
    assert sanitized[0]["content"] == "b"


def test_http_entry_preserves_frontend_response_contract() -> None:
    services = FakeServices("meal_record")
    client = TestClient(create_app(services))

    response = client.post(
        "/companion/ask",
        headers={"Authorization": "Bearer token"},
        json={"user_prompt": "早餐吃了一顆茶葉蛋", "temp_story": []},
    )

    assert response.status_code == 200
    assert response.json() == {
        "success": True,
        "companion_reply": "reply:meal_record",
        "intent_category": "meal_record",
        "meal_items": [
            {"name": "茶葉蛋", "quantity": 1, "unit": "顆", "meal_period": "早餐"}
        ],
        "query_date": None,
        "dietary_agent_error": None,
    }


@pytest.mark.parametrize("user_prompt", [None, "", "   ", 123])
def test_http_entry_preserves_bad_request_contract(user_prompt: Any) -> None:
    client = TestClient(create_app(FakeServices("general_chat")))

    response = client.post(
        "/companion/ask",
        json={"user_prompt": user_prompt, "temp_story": []},
    )

    assert response.status_code == 400
    assert response.json() == {
        "success": False,
        "error_code": "BAD_REQUEST",
        "error_message": "The 'user_prompt' field is required and must be a non-empty string.",
    }
