from __future__ import annotations

import json
import logging
from typing import Any

from .config import OPENAI_API_BASE, OPENAI_API_KEY, OPENAI_MODEL
from .models import DietRecord, DishAdvice, DishNutrition, HealthCondition, QuestionType, UserProfile

logger = logging.getLogger(__name__)

ANSWER_PROMPT = """
你是一位客觀、務實的飲食資訊助理。

你的任務不是重述資料，而是根據現有資料回答使用者真正想做的決定。請讓使用者看完後，能清楚理解每道料理的差異、取捨，以及目前較合理的選擇。

輸入資料包含：
- question：使用者的原始問題
- question_type：問題類型
- user_profile：使用者個人資訊與飲食目標
- health_condition：使用者記錄的慢性病
- weekly_diet_records：近期飲食紀錄
- dish_nutrition：知識圖譜查得的料理名稱與每份營養摘要
- disease_groups：本次問題所採用的慢性病規則

資料使用原則：
- 以 question 真正想解決的問題為回答核心。
- 綜合 dish_nutrition、user_profile、disease_groups 與相關的 weekly_diet_records 進行判斷。
- 只根據 dish_nutrition 中的料理名稱與營養成分評論料理。
- 不得推測、列舉或評論參考食譜中的食材、配菜、調味料、醃料或烹調方式。
- disease_groups 已完成疾病主題選擇：問題明確提到疾病時，以問題中的疾病為主；問題未提到疾病時，才以 health_condition 中的慢性病為主。
- 不得補造輸入中不存在的營養數值、疾病規則或個人狀況。
- dish_nutrition 中的數值只供內部判斷，不得在 key_reasons、suggestions 或 conclusion 中輸出任何營養成分的實際數值、差值、百分比、比例或每日門檻數字。
- 對使用者說明時，改用「較高」「較低」「接近」「差異有限」「差異明顯」等定性描述，並保留影響選擇的營養素名稱。

判斷方式：
- 先辨認使用者最重要的考量，例如慢性病、飲食目標、熱量、蛋白質或其他與問題相關的營養差異。
- 比較候選料理時，應同時考慮差異的方向與實際大小。
- 不要因為某道料理在單一營養素上略高，就直接判定它比較好；要判斷該差異是否足以影響整體選擇。
- 若某項優勢很小，但伴隨其他明顯不利差異，應清楚說明這項取捨。
- 不需要逐一列出所有營養素，只選擇真正影響本題判斷的資料。
- 不要把「存在估算誤差」直接等同於「資料不足」。
- 只要現有資料足以支持相對比較，就應提出清楚的相對選擇。
- 只有在缺少核心營養資料、料理無法匹配，或候選料理確實無法區分時，才使用「資料不足」。
- 若無法明確選出一道料理，請提供條件式選擇，例如「重視A時選甲，重視B時選乙」，並指出無法區分的真正原因。

回答方式：
- 比較題應先形成明確結論，再用最重要的營養差異解釋原因。
- 每一道候選料理都要產生一筆 dish_advice。
- key_reasons 應說明真正影響選擇的客觀依據，而不是重述所有欄位。
- suggestions 應提供外食者當下或當天實際做得到的做法。
- 不要建議使用者要求店家改變已完成料理的食譜或烹調流程。
- 可提供的實際做法包括份量調整、搭配選擇、避免額外添加、其他餐次的調整，或在特定需求下如何選擇。
- weekly_diet_records 只在確實與本題有關時使用；沒有相關紀錄時不必特別強調。
- 不要使用固定開場、固定結尾、冗長警語或重複免責聲明。
- 語調保持客觀、直接、自然，不說教，也不做醫療診斷。

suitability 使用原則：
- 「推薦」：在本次候選料理中，整體上相對符合使用者主要需求。
- 「較不建議」：與其他候選料理相比存在較明顯的不利取捨。
- 「適合」：單一道料理整體符合目前需求，但不是候選比較中的明確勝出者。
- 「可少量吃」：主要問題可透過控制份量降低。
- 「不建議」：現有資料顯示與主要需求存在明顯衝突。
- 「資料不足」：缺少完成基本判斷所必需的核心資料；不得只因資料是估算值就選擇此項。

key_reasons：
- 優先呈現二至三個最能影響決策的理由。
- 使用營養數值進行內部比較，但輸出只呈現比較後的方向與實際意義，不列出原始值或計算結果。
- 小幅差異應描述為「接近」或「差異有限」，不要誇大。
- 理由必須和 suitability 及 conclusion 一致。

suggestions：
- 每道料理至少提供一項具體、可實行且與該料理評估相關的建議。
- 避免只寫「均衡飲食」「適量攝取」「注意健康」等空泛內容。
- 不得根據參考食譜食材產生建議。

conclusion：
- 放在所有 dish_advice 之後。
- 第一個重點應直接回答使用者的問題，例如指出目前較建議的料理。
- 接著簡潔說明最關鍵的差異與取捨。
- 若有慢性病或飲食目標，說明它如何影響本次選擇。
- 不要只重複 suitability，也不要把判斷完全丟回給使用者。
- 只有證據無法區分時，才使用條件式結論。

只回傳合法 JSON，不要加入 Markdown、程式碼區塊或 JSON 以外的文字：

{
  "dish_advice": [
    {
      "dish_name": "必須完全使用輸入中的候選料理名稱",
      "suitability": "推薦|較不建議|適合|可少量吃|不建議|資料不足",
      "key_reasons": [
        "影響本題選擇的客觀理由"
      ],
      "suggestions": [
        "外食者實際可以執行的建議"
      ]
    }
  ],
  "conclusion": "直接回答問題並統整主要差異、取捨與選擇方向"
}
""".strip()


class AnswerGenerator:
    def __init__(self, *, openai_api_key: str = OPENAI_API_KEY,
                 openai_api_base: str = OPENAI_API_BASE, model: str = OPENAI_MODEL) -> None:
        self.openai_api_key = openai_api_key
        self.openai_api_base = openai_api_base
        self.model = model
        self._client = None

    def generate(self, *, question: str, question_type: QuestionType, user_profile: UserProfile,
                 health_condition: HealthCondition, dish_nutrition: list[DishNutrition],
                 weekly_diet_records: list[DietRecord], disease_groups: list[dict]) -> dict:
        if not self.openai_api_key or self.openai_api_key.strip() == "dummy-key":
            raise RuntimeError("LLM answer generation requires OPENAI_API_KEY.")
        context = {"question": question, "question_type": question_type,
                   "user_profile": user_profile.model_dump(),
                   "health_condition": health_condition.model_dump(),
                   "weekly_diet_records": [record.model_dump() for record in weekly_diet_records],
                   "dish_nutrition": [dish.model_dump() for dish in dish_nutrition],
                   "disease_groups": disease_groups}
        messages = [
            {"role": "system", "content": ANSWER_PROMPT},
            {"role": "user", "content": json.dumps(context, ensure_ascii=False)},
        ]
        # One repair pass keeps the public response contract stable without deciding content in code.
        for attempt in range(2):
            content = self._complete(messages)
            try:
                parsed = self._parse_json(content)
                self.validate_answer(parsed, dish_nutrition)
                break
            except (ValueError, TypeError, KeyError) as exc:
                if attempt:
                    raise RuntimeError("LLM answer failed evidence/output validation after one retry.") from exc
                logger.warning("Repairing answer contract: %s", exc)
                messages.extend([
                    {"role": "assistant", "content": content},
                    {"role": "user", "content": f"請修正以下錯誤，重新輸出完整 JSON：{exc}"},
                ])
        parsed["dish_advice"] = self.attach_match_metadata(parsed["dish_advice"], dish_nutrition)
        return parsed

    @staticmethod
    def validate_answer(parsed: dict, dishes: list[DishNutrition]) -> None:
        advice = [DishAdvice.model_validate(item) for item in parsed.get("dish_advice", [])]
        names = [d.dish_name for d in dishes]
        if len(advice) != len(names) or {a.dish_name for a in advice} != set(names):
            raise ValueError("dish_advice 必須剛好涵蓋所有候選料理，不可新增或重複。")
        conclusion = parsed.get("conclusion")
        if not isinstance(conclusion, str) or not conclusion.strip():
            raise ValueError("conclusion 不可為空。")
        for item in advice:
            if not item.key_reasons or not item.suggestions:
                raise ValueError("每道料理需合法 suitability、非空理由與建議。")

    @staticmethod
    def attach_match_metadata(advice: list[dict], dishes: list[DishNutrition]) -> list[dict]:
        by_name = {d.dish_name: d for d in dishes}
        fields = ("matched_name", "matched_type", "match_score", "match_reason")
        return [DishAdvice.model_validate({
            **item, **{field: getattr(by_name[item["dish_name"]], field) for field in fields}
        }).model_dump() for item in advice]

    @property
    def client(self) -> Any:
        if self._client is None:
            from openai import OpenAI
            self._client = OpenAI(api_key=self.openai_api_key, base_url=self.openai_api_base,
                                  timeout=60.0, max_retries=1)
        return self._client

    def _complete(self, messages: list[dict[str, str]]) -> str:
        from openai import OpenAIError
        try:
            response = self.client.chat.completions.create(
                model=self.model, messages=messages, response_format={"type": "json_object"},
            )
        except OpenAIError as exc:
            raise RuntimeError("LLM service unavailable; please retry later.") from exc
        content = response.choices[0].message.content
        if not content:
            raise RuntimeError("LLM returned empty answer.")
        return content

    @staticmethod
    def _parse_json(text: str) -> dict:
        cleaned = text.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.strip("`").strip()
            if cleaned.lower().startswith("json"):
                cleaned = cleaned[4:].strip()
        parsed = json.loads(cleaned)
        if not isinstance(parsed, dict):
            raise ValueError("Answer response must be a JSON object.")
        return parsed
