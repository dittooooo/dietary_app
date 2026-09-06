from __future__ import annotations

import asyncio
import json
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo

import httpx

from .config import Settings
from .prompts import ANALYSIS_TOOLS, load_analysis_prompt, load_translation_prompt
from .trace import TRACE_HEADER, get_trace_id, summarize, trace, trace_payload


class OpenAIServiceError(RuntimeError):
    pass


def sanitize_temp_story(value: Any) -> list[dict[str, str]]:
    if not isinstance(value, list):
        return []

    sanitized: list[dict[str, str]] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        role = item.get("role")
        content = item.get("content")
        if role not in {"user", "assistant"} or not isinstance(content, str):
            continue
        sanitized.append({"role": role, "content": content.strip()[:300]})
    return sanitized[-3:]


def sanitize_screening(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict):
        return {
            "should_handle": False,
            "intent_category": "general_chat",
            "question_type": None,
            "confidence": 0,
            "dish_info_list": {},
            "meal_items": [],
            "query_date": None,
        }

    result = dict(raw)
    if not isinstance(result.get("meal_items"), list):
        result["meal_items"] = []
    if not result.get("query_date"):
        result["query_date"] = None

    dish_info_list: dict[str, float | int] = {}
    for item in result["meal_items"]:
        if not isinstance(item, dict) or not item.get("name"):
            continue
        quantity = item.get("quantity")
        amount = quantity if isinstance(quantity, (int, float)) and quantity > 0 else 1
        dish_info_list[str(item["name"])] = amount
    result["dish_info_list"] = dish_info_list

    if result.get("intent_category") != "dish_advice":
        result["question_type"] = "not_applicable"
    elif not result.get("question_type"):
        result["question_type"] = "unknown"
    return result


def sanitize_emotion(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict):
        return {
            "primary_emotion": "neutral",
            "psychological_context": "other_general_chat",
            "companion_tone": "neutral",
            "evidence": [],
        }
    return {
        "primary_emotion": raw.get("primary_emotion") or "neutral",
        "psychological_context": raw.get("psychological_context") or "other_general_chat",
        "companion_tone": raw.get("companion_tone") or "neutral",
        "evidence": raw.get("evidence") if isinstance(raw.get("evidence"), list) else [],
    }


def build_dietary_agent_request(screening: dict[str, Any], message: str) -> dict[str, Any] | None:
    if not screening or not screening.get("should_handle"):
        return None
    question = message.strip() if isinstance(message, str) else ""
    question_type = screening.get("question_type")
    dish_info_list = screening.get("dish_info_list") or {}
    if not question or question_type not in {"single_dish", "dish_comparison"}:
        return None
    if not isinstance(dish_info_list, dict) or not dish_info_list:
        return None
    return {
        "question": question,
        "question_type": question_type,
        "dish_info_list": [
            {
                "dish_name": dish_name,
                "amount": amount if isinstance(amount, (int, float)) and amount > 0 else 1,
            }
            for dish_name, amount in dish_info_list.items()
        ],
    }


class WorkflowServices:
    def __init__(self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None) -> None:
        self.settings = settings
        self.analysis_prompt = load_analysis_prompt(settings.prompt_dir)
        self.translation_prompt = load_translation_prompt(settings.prompt_dir)
        self._transport = transport

    async def prepare(self, user_prompt: str, temp_story: list[dict[str, str]]) -> dict[str, Any]:
        trace("IntakeAgent", "OPENAI_ANALYSIS", "呼叫 OpenAI 分析意圖、情緒、料理與份量")
        analysis = await self._analyze(user_prompt, temp_story)
        screening = analysis["screening"]
        trace_payload("IntakeAgent", "OUTPUT", "analysis", analysis)

        if (
            screening.get("intent_category") == "dish_advice"
            and isinstance(screening.get("dish_info_list"), dict)
            and screening["dish_info_list"]
        ):
            trace("TranslationAgent", "OPENAI_TRANSLATION", "標準化料理名稱供下游營養查詢")
            original_entries = list(screening["dish_info_list"].items())
            translated = await asyncio.gather(
                *(self._translate_single_dish(name, amount) for name, amount in original_entries)
            )
            screening["dish_info_list"] = dict(translated)
            trace_payload("TranslationAgent", "OUTPUT", "dish_info_list", screening["dish_info_list"])

        return {
            "user_prompt": user_prompt,
            "temp_story": temp_story,
            "screening": screening,
            "emotion": analysis["emotion"],
            "dietary_agent_request": build_dietary_agent_request(screening, user_prompt),
        }

    async def call_dietary_agent(
        self, request_body: dict[str, Any], authorization: str | None
    ) -> dict[str, Any]:
        headers = {"Content-Type": "application/json", TRACE_HEADER: get_trace_id()}
        if authorization:
            headers["Authorization"] = authorization
        trace_payload("DietaryAgent", "INPUT", "request", request_body)
        trace("MAF", "CALL_DIETARY_AGENT", f"POST /dietary-agent/ask question={summarize(request_body.get('question'))}")
        async with httpx.AsyncClient(
            timeout=self.settings.request_timeout_seconds, transport=self._transport
        ) as client:
            response = await client.post(
                f"{self.settings.dietary_agent_api_url}/dietary-agent/ask",
                headers=headers,
                json=request_body,
            )
        response.raise_for_status()
        trace_payload("DietaryAgent", "OUTPUT", "response", response.json())
        trace("DietaryAgent", "RETURNED", f"飲食建議處理完成 HTTP {response.status_code}")
        return response.json()

    async def create_diet_records(
        self, records: list[dict[str, Any]], authorization: str | None
    ) -> dict[str, Any]:
        headers = {"Content-Type": "application/json", TRACE_HEADER: get_trace_id()}
        if authorization:
            headers["Authorization"] = authorization
        trace("MAF", "SAVE_RECORDS", f"呼叫飲食紀錄 API，共 {len(records)} 筆")
        async with httpx.AsyncClient(
            timeout=self.settings.request_timeout_seconds, transport=self._transport
        ) as client:
            response = await client.post(
                f"{self.settings.dietary_agent_api_url}/api/diet-records",
                headers=headers,
                json=records,
            )
        response.raise_for_status()
        trace("DietaryAgent", "RECORDS_SAVED", f"資料庫寫入完成 HTTP {response.status_code}")
        return response.json()

    async def fetch_dish_nutrition(self, dish_name: str) -> dict[str, float]:
        trace("MAF", "CALL_NUTRITION", f"查詢料理營養：{summarize(dish_name, 40)}")
        async with httpx.AsyncClient(
            timeout=self.settings.request_timeout_seconds, transport=self._transport
        ) as client:
            response = await client.post(
                f"{self.settings.dietary_agent_api_url}/dietary-agent/dish-nutrition",
                headers={"Content-Type": "application/json", TRACE_HEADER: get_trace_id()},
                json={"dish_name": dish_name},
            )
        response.raise_for_status()
        trace("NutritionistAgent", "RETURNED", f"營養查詢完成 HTTP {response.status_code}")
        root = response.json()
        data = root.get("data", root) if isinstance(root, dict) else {}
        nutrition = data.get("dish_nutrition", {}) if isinstance(data, dict) else {}
        nutrients = nutrition.get("nutrients", []) if isinstance(nutrition, dict) else []
        values: dict[str, float] = {}
        key_names = {
            "calories": ("熱量", "calories", "kcal"),
            "protein": ("蛋白質", "protein"),
            "fat": ("脂肪", "fat"),
            "carbohydrates": ("碳水", "carbohydrate", "carbs"),
        }
        for nutrient in nutrients:
            if not isinstance(nutrient, dict):
                continue
            name = str(nutrient.get("name") or "").lower()
            raw_amount = nutrient.get("amount_per_serving")
            try:
                amount = float(raw_amount)
            except (TypeError, ValueError):
                continue
            for key, aliases in key_names.items():
                if any(alias.lower() in name for alias in aliases):
                    values[key] = amount
                    break
        return values

    async def call_companion_reply(
        self,
        context: dict[str, Any],
        dietary_agent_response: dict[str, Any] | None,
        dietary_agent_error: str | None,
    ) -> str:
        body = {
            "user_prompt": context["user_prompt"],
            "screening": context["screening"],
            "emotion": context["emotion"],
            "dietary_agent_response": dietary_agent_response,
            "dietary_agent_error": dietary_agent_error,
            "temp_story": context["temp_story"],
        }
        trace_payload("CompanionAgent", "INPUT", "request", body)
        trace("MAF", "CALL_COMPANION", "呼叫 CompanionAgent 產生最終自然語言回覆")
        async with httpx.AsyncClient(
            timeout=self.settings.request_timeout_seconds, transport=self._transport
        ) as client:
            response = await client.post(
                f"{self.settings.companion_api_url}/companion/reply",
                headers={TRACE_HEADER: get_trace_id()},
                json=body,
            )
        response.raise_for_status()
        trace("CompanionAgent", "RETURNED", f"最終回覆完成 HTTP {response.status_code}")
        data = response.json()
        trace_payload("CompanionAgent", "OUTPUT", "response", data)
        reply = data.get("companion_reply")
        if not isinstance(reply, str):
            raise RuntimeError("Companion Agent returned an invalid reply.")
        return reply

    async def _analyze(
        self, user_prompt: str, temp_story: list[dict[str, str]]
    ) -> dict[str, dict[str, Any]]:
        local_time = datetime.now(ZoneInfo("Asia/Taipei")).strftime("%Y/%m/%d %H:%M:%S")
        history = "\n".join(
            f"{'使用者' if item['role'] == 'user' else '米粒'}: {item['content']}"
            for item in temp_story
        ) or "無歷史對話"
        prompt_with_time = (
            f'【歷史對話紀錄】:\n{history}\n\n當前系統時間: {local_time}\n'
            f'使用者最新輸入: "{user_prompt}"'
        )
        body = {
            "model": self.settings.openai_model,
            "parallel_tool_calls": True,
            "tool_choice": "auto",
            "tools": ANALYSIS_TOOLS,
            "instructions": self.analysis_prompt,
            "input": [
                {
                    "role": "user",
                    "content": [{"type": "input_text", "text": prompt_with_time}],
                }
            ],
        }
        response_json = await self._post_openai("/v1/responses", body)
        by_name: dict[str, Any] = {}
        for item in response_json.get("output", []):
            if item.get("type") != "function_call":
                continue
            try:
                by_name[item.get("name")] = json.loads(item.get("arguments") or "{}")
            except (TypeError, json.JSONDecodeError):
                by_name[item.get("name")] = None
        return {
            "screening": sanitize_screening(by_name.get("screen_user_request")),
            "emotion": sanitize_emotion(by_name.get("analyze_emotion")),
        }

    async def _translate_single_dish(self, dish_name: str, amount: float | int) -> tuple[str, float | int]:
        translated = await self._translate_dishes([dish_name])
        combined = "".join(translated) if isinstance(translated, list) else ""
        return ((combined.strip() or dish_name), amount)

    async def _translate_dishes(self, dishes: list[str]) -> list[str]:
        if not dishes:
            return []
        body = {
            "model": self.settings.openai_model,
            "messages": [
                {"role": "system", "content": self.translation_prompt},
                {"role": "user", "content": json.dumps(dishes, ensure_ascii=False)},
            ],
            "response_format": {"type": "json_object"},
        }
        try:
            response_json = await self._post_openai("/v1/chat/completions", body)
            content = response_json["choices"][0]["message"]["content"].strip()
            parsed = json.loads(content)
            translated = parsed.get("translated_dishes")
            if isinstance(translated, list):
                return [str(item) for item in translated]
        except Exception:
            return dishes
        return dishes

    async def _post_openai(self, path: str, body: dict[str, Any]) -> dict[str, Any]:
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.settings.openai_api_key}",
        }
        try:
            trace("OpenAI", "REQUEST", f"{path} model={body.get('model')}")
            async with httpx.AsyncClient(
                timeout=self.settings.request_timeout_seconds, transport=self._transport
            ) as client:
                response = await client.post(f"https://api.openai.com{path}", headers=headers, json=body)
            if response.is_error:
                raise OpenAIServiceError(f"OpenAI API error {response.status_code}: {response.text}")
            trace("OpenAI", "RETURNED", f"{path} HTTP {response.status_code}")
            return response.json()
        except OpenAIServiceError:
            raise
        except Exception as error:
            raise OpenAIServiceError(str(error)) from error
