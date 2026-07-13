from __future__ import annotations

import json
from collections import Counter
from typing import Any, Dict, List, Optional

from .config import OPENAI_API_BASE, OPENAI_API_KEY, OPENAI_MODEL
from .models import DietRecord, DishAdvice, DishNutrition, HealthCondition, QuestionType, UserProfile


ANSWER_PROMPT = """
你是飲食建議多代理人架構中的 Nutrition Agent。
你只根據 GraphRAG 檢索結果與使用者資料回答，不要杜撰沒有依據的數值。
dish_nutrition 中的數值只供內部排序與判斷參考，因為使用情境是點餐前估計，不是精準檢驗。

輸出規則：
- 使用繁體中文。
- 回覆要精簡，聚焦重點。
- 每道料理最多給 3 個重點理由。
- 結論要直接回答使用者問題。
- 回答必須根據 dish_nutrition，不能自行編造營養數值。
- 熱量只能使用 calculation_method 為 macro_calculation 的結果；若缺少熱量，不可自行補值。
- dish_advice 與 conclusion 不可以輸出任何實際營養數字、份量數字或單位，例如 kcal、mg、g、克、毫克、%、每日上限。
- 建議文字只能使用「可能較高」「相對較高」「偏高」「較低」「資料不足」「可作為參考」這類定性描述。
- retrieval_strategy 是 ingredient_fallback 時，要說明是依可辨識食材推估。
- 若 calorie_status 是 insufficient_macros 或沒有熱量，請保守標示「資料不足」或「可少量吃」。
- 若是單一道料理，suitability 使用「適合 / 可少量吃 / 不建議 / 資料不足」之一。
- 若是多道料理比較，結論一定要從候選料理中選出一項相對最建議的選擇，不可以回答「都不理想」或不選。
- 若是多道料理比較，dish_advice 必須剛好有一個料理的 suitability 是「推薦」，其他候選料理使用「較不建議」「可少量吃」或「資料不足」。
- 若是多道料理比較，conclusion 的第一句請使用「推薦選擇 <料理名>，...」。
- 整體宗旨是「不限制使用者吃什麼，而是幫助使用者做出相對健康的選擇」。
- 慢性疾病只根據 health_condition，不要從 question 文字推測。
- 建議除了引用圖譜中的料理、營養與疾病規則，也要納入 user_profile 與 weekly_diet_records。
- 若近期飲食偏油、偏鹹、偏甜，請溫和提醒；若近期飲食均衡，可允許較彈性的份量建議。
- 不要輸出冗長圖譜路徑說明。
- 不要逐筆列出所有 graph rows。
- 最後加一句：實際仍需依個人血糖、病況與醫囑調整。

請輸出 JSON：
{
  "dish_advice": [
    {
      "dish_name": "...",
      "suitability": "推薦|較不建議|適合|可少量吃|不建議|資料不足",
      "key_reasons": ["...", "..."],
      "suggestions": ["...", "..."]
    }
  ],
  "conclusion": "..."
}
""".strip()


# 負責把圖譜檢索結果、營養摘要與使用者背景交給 OpenAI 產生建議。
class AnswerGenerator:
    # 初始化 OpenAI 連線設定；client 採 lazy loading，真正呼叫時才建立。
    def __init__(
        self,
        *,
        openai_api_key: str = OPENAI_API_KEY,
        openai_api_base: str = OPENAI_API_BASE,
        model: str = OPENAI_MODEL,
    ) -> None:
        self.openai_api_key = openai_api_key
        self.openai_api_base = openai_api_base
        self.model = model
        self._client: Optional[Any] = None

    # 組合 LLM 所需上下文、呼叫模型，並整理成 API 可回傳的建議格式。
    def generate(
        self,
        *,
        question: str,
        question_type: QuestionType,
        user_profile: UserProfile,
        health_condition: HealthCondition,
        weekly_diet_records: List[DietRecord],
        dish_nutrition: List[DishNutrition],
        graph_rows: List[Dict[str, Any]],
    ) -> Dict[str, Any]:
        # context 是 LLM 看得到的完整輸入，包含原始問題、個人資料、近期飲食與圖譜結果。
        context = {
            "question": question,
            "question_type": question_type,
            "user_profile": user_profile.model_dump(),
            "health_condition": health_condition.model_dump(),
            "weekly_diet_records": [record.model_dump() for record in weekly_diet_records],
            "user_context_summary": self.summarize_user_context(
                user_profile,
                health_condition,
                weekly_diet_records,
            ),
            "dish_nutrition": [item.model_dump() for item in dish_nutrition],
            "graph_rows": graph_rows[:80],
            "retrieval_notes": {
                "calories_are_recalculated_from_macros": True,
                "ingredient_fallback_means_estimated_nutrition": True,
                "nutrition_numbers_are_for_internal_reference_only": True,
                "do_not_include_nutrition_numbers_in_advice_text": True,
            },
        }

        if not self.openai_api_key or self.openai_api_key.strip() == "dummy-key":
            raise RuntimeError(
                "LLM answer generation requires OPENAI_API_KEY. "
                "Set a real API key because nutrition_agent no longer uses fallback conclusions."
            )

        parsed = self.generate_with_llm(
            context=context,
            question_type=question_type,
            dish_nutrition=dish_nutrition,
        )
        parsed["dish_advice"] = [DishAdvice(**item).model_dump() for item in parsed.get("dish_advice", [])]
        parsed["conclusion"] = str(parsed.get("conclusion", "")).strip()
        if question_type == "dish_comparison":
            # 比較題必須剛好選出一個推薦料理，避免回覆模糊而無法回答使用者問題。
            parsed = self.normalize_comparison_advice(
                parsed,
                dish_nutrition,
            )
        # 回答完成後補上圖譜配對 metadata，並移除模型可能輸出的具體營養數字。
        parsed = self.attach_match_metadata_to_advice(parsed, dish_nutrition)
        parsed = self.sanitize_nutrition_numbers(parsed)
        return parsed

    # 實際呼叫 LLM，並在比較題沒有明確選項時要求模型重試一次。
    def generate_with_llm(
        self,
        *,
        context: Dict[str, Any],
        question_type: QuestionType,
        dish_nutrition: List[DishNutrition],
    ) -> Dict[str, Any]:
        messages = [
            {"role": "system", "content": ANSWER_PROMPT},
            {"role": "user", "content": json.dumps(context, ensure_ascii=False, indent=2)},
        ]
        parsed = self._parse_json(self._complete(messages))
        if question_type != "dish_comparison" or self.has_llm_comparison_choice(parsed, dish_nutrition):
            return parsed

        # 第二輪提示只修正「沒有明確推薦」這件事，不重新改變輸出 schema。
        correction_prompt = (
            "你的上一版回答沒有明確從候選料理中選出一項。"
            "請重新輸出同樣 JSON 格式。"
            "dish_advice 必須剛好有一個 suitability 是「推薦」，其他候選料理使用「較不建議」「可少量吃」或「資料不足」。"
            "conclusion 第一句必須使用「推薦選擇 <料理名>，...」。"
            "只能從 dish_nutrition 裡出現的 dish_name 選一項。"
            "dish_advice 與 conclusion 不可以輸出任何實際營養數字或單位，只能用定性描述。"
        )
        retry_messages = messages + [
            {"role": "assistant", "content": json.dumps(parsed, ensure_ascii=False)},
            {"role": "user", "content": correction_prompt},
        ]
        retried = self._parse_json(self._complete(retry_messages))
        if self.has_llm_comparison_choice(retried, dish_nutrition):
            return retried
        if self.has_llm_comparison_choice(parsed, dish_nutrition, require_conclusion=False):
            return parsed
        raise RuntimeError("LLM answer did not mark exactly one recommended dish for comparison after retry.")

    # 標準化比較題結果，確保每個候選料理都有建議且只有一個推薦。
    def normalize_comparison_advice(
        self,
        parsed: Dict[str, Any],
        dish_nutrition: List[DishNutrition],
    ) -> Dict[str, Any]:
        if not dish_nutrition:
            return parsed

        chosen = self.extract_llm_choice(parsed, dish_nutrition)
        if not chosen:
            raise RuntimeError("LLM answer did not choose a recommended dish.")

        advice_by_name = {item.get("dish_name"): item for item in parsed.get("dish_advice", [])}
        normalized_advice = []
        for item in dish_nutrition:
            existing = advice_by_name.get(item.dish_name, {})
            existing["dish_name"] = item.dish_name
            existing["suitability"] = self.normalized_suitability(item, item.dish_name == chosen)
            existing.setdefault("key_reasons", ["依圖譜營養與個人近期飲食狀況排序。"])
            existing.setdefault("suggestions", ["依份量與當日其他餐點彈性調整。"])
            normalized_advice.append(DishAdvice(**existing).model_dump())

        parsed["dish_advice"] = normalized_advice
        return parsed

    # 檢查 LLM 回答是否已經從候選料理中明確選出一個推薦。
    @staticmethod
    def has_llm_comparison_choice(
        parsed: Dict[str, Any],
        dish_nutrition: List[DishNutrition],
        *,
        require_conclusion: bool = False,
    ) -> bool:
        chosen = AnswerGenerator.extract_llm_choice(parsed, dish_nutrition)
        if not chosen:
            return False
        if not require_conclusion:
            return True
        conclusion = str(parsed.get("conclusion", ""))
        return chosen in conclusion and ("建議" in conclusion or "選擇" in conclusion or "推薦" in conclusion)

    # 從 dish_advice 或 conclusion 中解析 LLM 實際推薦的料理名稱。
    @staticmethod
    def extract_llm_choice(parsed: Dict[str, Any], dish_nutrition: List[DishNutrition]) -> Optional[str]:
        dish_names = {item.dish_name for item in dish_nutrition}
        advice = parsed.get("dish_advice", [])
        recommended = [
            item.get("dish_name")
            for item in advice
            if item.get("suitability") == "推薦" and item.get("dish_name") in dish_names
        ]
        unique_recommended = list(dict.fromkeys(recommended))
        if len(unique_recommended) == 1:
            return unique_recommended[0]

        conclusion = str(parsed.get("conclusion", ""))
        mentioned = [name for name in dish_names if name in conclusion]
        if len(mentioned) == 1 and any(marker in conclusion for marker in ("建議", "選擇", "推薦")):
            return mentioned[0]

        markers = ("較建議選擇", "建議選擇", "推薦", "選擇", "建議")
        marker_positions = [conclusion.find(marker) for marker in markers if conclusion.find(marker) >= 0]
        if not marker_positions:
            return None
        start = min(marker_positions)
        after_marker = conclusion[start:]
        ordered_mentions = sorted(
            ((after_marker.find(name), name) for name in dish_names if after_marker.find(name) >= 0),
            key=lambda pair: pair[0],
        )
        if ordered_mentions:
            return ordered_mentions[0][1]
        return None

    # 依資料完整度與是否被選中，決定比較題每道料理的 suitability。
    @staticmethod
    def normalized_suitability(item: DishNutrition, chosen: bool) -> str:
        calorie_statuses = {nutrient.calorie_status for nutrient in item.nutrients if nutrient.calorie_status}
        if "insufficient_macros" in calorie_statuses or "unit_invalid" in calorie_statuses:
            return "資料不足"
        return "推薦" if chosen else "較不建議"

    # 把圖譜配對名稱、類型、分數與原因附加到 LLM 的 dish_advice。
    @staticmethod
    def attach_match_metadata_to_advice(
        parsed: Dict[str, Any],
        dish_nutrition: List[DishNutrition],
    ) -> Dict[str, Any]:
        if not dish_nutrition:
            return parsed

        by_user_name = {item.dish_name: item for item in dish_nutrition}
        by_matched_name = {item.matched_name: item for item in dish_nutrition if item.matched_name}
        normalized_advice = []
        for advice in parsed.get("dish_advice", []):
            advice = dict(advice)
            source = by_user_name.get(advice.get("dish_name")) or by_matched_name.get(advice.get("dish_name"))
            if source is None and len(dish_nutrition) == 1:
                source = dish_nutrition[0]
            if source is not None:
                advice["dish_name"] = source.dish_name
                advice["matched_name"] = source.matched_name
                advice["matched_type"] = source.matched_type
                advice["match_score"] = source.match_score
                advice["match_reason"] = source.match_reason
            normalized_advice.append(DishAdvice(**advice).model_dump())
        parsed["dish_advice"] = normalized_advice
        return parsed

    # 清理建議文字中的數值與單位，遵守不輸出具體營養數字的產品規則。
    @classmethod
    def sanitize_nutrition_numbers(cls, parsed: Dict[str, Any]) -> Dict[str, Any]:
        parsed["conclusion"] = cls.sanitize_advice_text(str(parsed.get("conclusion", "")))
        sanitized_advice = []
        for item in parsed.get("dish_advice", []):
            item = dict(item)
            item["key_reasons"] = [cls.sanitize_advice_text(str(reason)) for reason in item.get("key_reasons", [])]
            item["suggestions"] = [cls.sanitize_advice_text(str(suggestion)) for suggestion in item.get("suggestions", [])]
            sanitized_advice.append(item)
        parsed["dish_advice"] = sanitized_advice
        return parsed

    # 將 kcal、mg、g、百分比等具體數值改成定性描述。
    @staticmethod
    def sanitize_advice_text(text: str) -> str:
        import re

        cleaned = re.sub(
            r"\d+(?:\.\d+)?\s*(?:kcal|卡|大卡|mg|毫克|g|克|%|公克|份|每日鈉攝取上限)",
            "相對偏高",
            text,
            flags=re.IGNORECASE,
        )
        cleaned = re.sub(r"高達\s*相對偏高", "可能偏高", cleaned)
        cleaned = re.sub(r"超過[^，。；;]*?(?:上限|建議量)", "可能超過建議範圍", cleaned)
        cleaned = re.sub(r"\d+(?:\.\d+)?", "", cleaned)
        cleaned = re.sub(r"\s+", " ", cleaned).strip()
        return cleaned

    # 把身高體重、慢性病與近期飲食紀錄整理成 LLM 容易使用的摘要。
    @staticmethod
    def summarize_user_context(
        user_profile: UserProfile,
        health_condition: HealthCondition,
        weekly_diet_records: List[DietRecord],
    ) -> Dict[str, Any]:
        bmi: Optional[float] = None
        bmi_category = "未知"
        if user_profile.height_cm and user_profile.weight_kg and user_profile.height_cm > 0:
            height_m = user_profile.height_cm / 100
            bmi = round(user_profile.weight_kg / (height_m * height_m), 1)
            if bmi >= 27:
                bmi_category = "肥胖"
            elif bmi >= 24:
                bmi_category = "過重"
            elif bmi >= 18.5:
                bmi_category = "正常"
            else:
                bmi_category = "過輕"

        patterns: Counter[str] = Counter()
        for record in weekly_diet_records:
            text = f"{record.dish_name or ''} {record.note or ''}"
            if any(token in text for token in ("炸", "煎", "油", "雞排", "薯條", "鹽酥", "奶油", "起司")):
                patterns["oily"] += 1
            if any(token in text for token in ("鹹", "鹽", "滷", "泡麵", "醬", "火鍋", "湯麵")):
                patterns["salty"] += 1
            if any(token in text for token in ("甜", "糖", "飲料", "蛋糕", "餅乾", "手搖")):
                patterns["sweet"] += 1
            if any(token in text for token in ("蔬菜", "沙拉", "水果", "水煮", "清蒸", "地瓜", "燕麥")):
                patterns["balanced"] += 1

        return {
            "bmi": bmi,
            "bmi_category": bmi_category,
            "chronic_diseases": health_condition.chronic_diseases if health_condition.has_chronic_disease else [],
            "recent_patterns": dict(patterns),
            "weekly_record_count": len(weekly_diet_records),
        }

    # 延遲建立 OpenAI client，避免匯入模組時就產生外部連線依賴。
    @property
    def client(self) -> Any:
        if self._client is None:
            from openai import OpenAI

            self._client = OpenAI(api_key=self.openai_api_key, base_url=self.openai_api_base)
        return self._client

    # 呼叫 OpenAI Chat Completions API 並取回文字內容。
    def _complete(self, messages: List[Dict[str, str]]) -> str:
        response = self.client.chat.completions.create(
            model=self.model,
            messages=messages,
            temperature=0.0,
        )
        content = response.choices[0].message.content
        if not content:
            raise RuntimeError("LLM returned empty answer.")
        return content

    # 解析 LLM 回傳的 JSON，支援去除 ```json code fence。
    @staticmethod
    def _parse_json(text: str) -> Dict[str, Any]:
        cleaned = text.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.strip("`").strip()
            if cleaned.lower().startswith("json"):
                cleaned = cleaned[4:].strip()
        parsed = json.loads(cleaned)
        if not isinstance(parsed, dict):
            raise ValueError("Answer response must be a JSON object.")
        return parsed
