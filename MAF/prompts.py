from __future__ import annotations

from pathlib import Path


def _read_javascript_template(path: Path, constant_name: str) -> str:
    source = path.read_text(encoding="utf-8")
    marker = f"const {constant_name} = `"
    start = source.find(marker)
    if start < 0:
        raise RuntimeError(f"Cannot find {constant_name} in {path}")
    start += len(marker)
    end = source.find("`;", start)
    if end < 0:
        raise RuntimeError(f"Cannot find the end of {constant_name} in {path}")
    return source[start:end]


def load_analysis_prompt(prompt_dir: Path) -> str:
    return _read_javascript_template(prompt_dir / "analysisPrompt.js", "ANALYSIS_SYSTEM_PROMPT")


def load_translation_prompt(prompt_dir: Path) -> str:
    return _read_javascript_template(prompt_dir / "translationPrompt.js", "TRANSLATION_SYSTEM_PROMPT")


SCREEN_USER_REQUEST_TOOL = {
    "type": "function",
    "name": "screen_user_request",
    "description": (
        "Screen the user request to classify question type, intent, query date, "
        "and extract mentioned dishes into a 1D flat array."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "should_handle": {
                "type": "boolean",
                "description": "Whether this request should be processed by the companion agent.",
            },
            "intent_category": {
                "type": "string",
                "enum": ["dish_advice", "meal_record", "general_chat", "meal_query"],
            },
            "query_date": {
                "type": ["string", "null"],
                "description": (
                    "歷史飲食查詢 (meal_query) 時提取之目標日期，格式必須為 ISO YYYY-MM-DD"
                    "（例如 2026-06-19）。非歷史查詢意圖時設為 null。"
                ),
            },
            "question_type": {
                "type": "string",
                "enum": ["single_dish", "dish_comparison", "unknown", "not_applicable"],
                "description": (
                    "飲食諮詢時依餐點數量選 single_dish / dish_comparison / unknown；"
                    "非飲食諮詢 (meal_record, meal_query 或 general_chat) 一律選 not_applicable。"
                ),
            },
            "confidence": {"type": "number"},
            "meal_items": {
                "type": "array",
                "description": (
                    "一維餐點明細陣列。無論是記錄或諮詢，只要訊息中含有具體食物名稱，"
                    "均必須完整擷取至此列表中，絕不可傳回空陣列。僅非飲食主題問句"
                    "（如天氣）才傳回空陣列 []。"
                ),
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string", "description": "食物或飲料名稱，例如：蛋餅"},
                        "quantity": {
                            "type": "number",
                            "description": "數量，例如：1 (若未提及則設為 1)",
                        },
                        "unit": {
                            "type": "string",
                            "description": "單位，例如：份、碗、個 (若未提及則設為合理預設值)",
                        },
                        "meal_period": {
                            "type": "string",
                            "enum": ["早餐", "中餐", "晚餐", "其他"],
                            "description": "該餐點對應或推算之餐期。",
                        },
                    },
                    "required": ["name", "quantity", "unit", "meal_period"],
                },
            },
        },
        "required": [
            "should_handle",
            "intent_category",
            "question_type",
            "confidence",
            "meal_items",
        ],
        "additionalProperties": False,
    },
}


ANALYZE_EMOTION_TOOL = {
    "type": "function",
    "name": "analyze_emotion",
    "description": (
        "Analyze the user's emotional state, psychological context, and key phrases "
        "to guide interactive companion replies."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "primary_emotion": {
                "type": "string",
                "enum": ["neutral", "joy", "anxiety", "guilt", "stress", "frustration", "fatigue"],
            },
            "psychological_context": {
                "type": "string",
                "enum": [
                    "work_overtime_stress",
                    "diet_relapse_guilt",
                    "weather_or_mood",
                    "social_dining",
                    "routine_craving",
                    "other_general_chat",
                ],
                "description": "The primary situational category driving the user's message.",
            },
            "companion_tone": {
                "type": "string",
                "enum": ["comforting", "encouraging", "playful", "neutral"],
            },
            "evidence": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Key emotion words or situational phrases extracted from the user's prompt.",
            },
        },
        "required": ["primary_emotion", "psychological_context", "companion_tone", "evidence"],
        "additionalProperties": False,
    },
}


ANALYSIS_TOOLS = [SCREEN_USER_REQUEST_TOOL, ANALYZE_EMOTION_TOOL]
