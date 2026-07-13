from __future__ import annotations

import logging
from typing import Any, Dict, List

from .answer_generator import AnswerGenerator
from .config import DEFAULT_TOP_N_ROWS, NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER
from .dish_matcher import DishMatcher
from .models import DishNutrition, HealthCondition, NutrientAmount, NutritionAgentRequest, NutritionAgentResponse, UserProfile
from .nutrition_calculator import NutritionCalculator
from .retriever import GraphRetriever
from .text_to_cypher import (
    TextToCypherTranslator,
    extract_dish_candidates,
    infer_question_type,
    normalize_request_payload,
)


logger = logging.getLogger(__name__)


# 串接料理名稱解析、Neo4j 檢索、營養彙總與 LLM 回答產生的主要協調器。
class NutritionAgent:
    # 初始化所有子模組，讓一次 /ask 請求可以共用同一組 Neo4j driver。
    def __init__(
        self,
        *,
        neo4j_uri: str = NEO4J_URI,
        neo4j_user: str = NEO4J_USER,
        neo4j_password: str = NEO4J_PASSWORD,
    ) -> None:
        self.retriever = GraphRetriever(neo4j_uri, neo4j_user, neo4j_password)
        self.translator = TextToCypherTranslator()
        self.dish_matcher = DishMatcher(self.retriever.driver)
        self.nutrition_calculator = NutritionCalculator()
        self.answer_generator = AnswerGenerator()

    # 關閉 Neo4j 連線資源，通常用於服務關閉或測試清理。
    def close(self) -> None:
        self.retriever.close()

    # 執行完整問答生命週期，從 request 轉成圖譜資料，再產生飲食建議。
    def ask(self, request: NutritionAgentRequest) -> NutritionAgentResponse:
        # 請求中的個人資料都允許省略；缺少時用空模型，避免後續流程一直處理 None。
        user_profile = request.user_profile or UserProfile()
        health_condition = request.health_condition or HealthCondition()
        weekly_records = request.weekly_diet_records or []
        effective_question_type = infer_question_type(request.question, request.question_type)

        # 第一次 payload 只放原始輸入，先用來抽出料理候選名稱。
        full_payload = normalize_request_payload(
            question=request.question,
            question_type=effective_question_type,
            user_profile=user_profile,
            health_condition=health_condition,
            weekly_diet_records=weekly_records,
            dish_names=request.dish_names,
        )

        dish_candidates = extract_dish_candidates(full_payload)
        logger.info("[NutritionAgent] dish_candidates=%s", dish_candidates)

        # 先把使用者輸入的料理名稱對齊圖譜中的 Dish 或 FoodItem，決定後續檢索策略。
        match_results = self.dish_matcher.match_dishes(dish_candidates)
        logger.info("[NutritionAgent] dish_match=%s", match_results)

        # 第二次 payload 帶入候選料理與配對結果，讓 Cypher 產生器可以查正確的圖譜節點。
        full_payload = normalize_request_payload(
            question=request.question,
            question_type=effective_question_type,
            user_profile=user_profile,
            health_condition=health_condition,
            weekly_diet_records=weekly_records,
            dish_names=request.dish_names,
            dish_candidates=dish_candidates,
            dish_match_results=match_results,
        )
        translated = self.translator.translate(full_payload)
        cypher = translated["cypher"]
        question_type = translated.get("question_type", effective_question_type)  # type: ignore[assignment]
        logger.info("[NutritionAgent] generated_cypher=%s", cypher)

        # 使用受保護的 read-only Cypher 查 Neo4j，回來的是尚未彙總的營養列資料。
        rows = self.retriever.retrieve(cypher)
        missing_candidates = self._missing_candidates_from_rows(dish_candidates, match_results, rows)
        if missing_candidates:
            # 若料理配對成功但沒有查到營養列，改用食材 fallback 再查一次，盡量保留回覆能力。
            fallback_results = [
                {
                    "input_name": candidate,
                    "matched_dish_name": None,
                    "match_score": 0,
                    "match_reason": "no nutrition rows from dish match",
                    "retrieval_strategy": "ingredient_fallback",
                }
                for candidate in missing_candidates
            ]
            fallback_payload = normalize_request_payload(
                question=request.question,
                question_type=effective_question_type,
                user_profile=user_profile,
                health_condition=health_condition,
                weekly_diet_records=weekly_records,
                dish_names=missing_candidates,
                dish_candidates=missing_candidates,
                dish_match_results=fallback_results,
            )
            translated_fallback = self.translator.translate(fallback_payload)
            fallback_cypher = translated_fallback["cypher"]
            fallback_rows = self.retriever.retrieve(fallback_cypher)
            rows.extend(fallback_rows)
            logger.info(
                "[NutritionAgent] ingredient_fallback_retry missing_candidates=%s fallback_row_count=%s",
                missing_candidates,
                len(fallback_rows),
            )
        logger.info("[NutritionAgent] graph_row_count=%s", len(rows))
        dish_nutrition, nutrition_debug = self.nutrition_calculator.summarize_and_recalculate(rows)
        dish_nutrition = self._ensure_candidate_nutrition(
            dish_nutrition,
            dish_candidates,
            match_results,
            question_type,  # type: ignore[arg-type]
        )
        logger.info("[NutritionAgent] nutrition_debug=%s", nutrition_debug)

        # 最後把使用者資料、近期飲食、圖譜摘要與營養結果交給 LLM 產生自然語言建議。
        answer_payload = self.answer_generator.generate(
            question=request.question,
            question_type=question_type,  # type: ignore[arg-type]
            user_profile=user_profile,
            health_condition=health_condition,
            weekly_diet_records=weekly_records,
            dish_nutrition=dish_nutrition,
            graph_rows=rows[:DEFAULT_TOP_N_ROWS],
        )

        return NutritionAgentResponse(
            question=request.question,
            question_type=question_type,  # type: ignore[arg-type]
            dish_nutrition=dish_nutrition,
            dish_advice=answer_payload.get("dish_advice", []),
            conclusion=answer_payload.get("conclusion", ""),
        )

    # 找出候選料理中沒有從 Neo4j 查到任何營養資料的項目。
    @staticmethod
    def _missing_candidates_from_rows(
        dish_candidates: List[str],
        match_results: List[Dict[str, Any]],
        rows: List[Dict[str, Any]],
    ) -> List[str]:
        row_dish_names = {
            str(name)
            for row in rows
            for name in (row.get("dish_name"), row.get("matched_dish_name"))
            if name
        }
        expected_name_by_input = {
            str(item.get("input_name")): str(item.get("matched_dish_name") or item.get("input_name"))
            for item in match_results
        }
        expected_name_by_input.update(
            {
                str(item.get("raw_input_name")): str(item.get("matched_dish_name") or item.get("input_name"))
                for item in match_results
                if item.get("raw_input_name")
            }
        )
        return [
            candidate
            for candidate in dish_candidates
            if expected_name_by_input.get(candidate, candidate) not in row_dish_names and candidate not in row_dish_names
        ]

    # 比較題時補齊缺資料的候選料理，確保回覆仍涵蓋每個比較選項。
    @staticmethod
    def _ensure_candidate_nutrition(
        dish_nutrition: List[DishNutrition],
        dish_candidates: List[str],
        match_results: List[Dict[str, Any]],
        question_type: str,
    ) -> List[DishNutrition]:
        if question_type != "dish_comparison":
            return dish_nutrition

        existing_names = {item.dish_name for item in dish_nutrition}
        strategy_by_name = {
            str(item.get("input_name")): str(item.get("retrieval_strategy") or "unknown")
            for item in match_results
        }
        match_by_name = {
            str(item.get("input_name")): item
            for item in match_results
        }
        display_name_by_raw = {
            str(item.get("raw_input_name")): str(item.get("input_name") or item.get("raw_input_name"))
            for item in match_results
            if item.get("raw_input_name")
        }
        completed = list(dish_nutrition)
        for candidate in dish_candidates:
            display_name = display_name_by_raw.get(candidate, candidate)
            if display_name in existing_names:
                continue
            # 沒有營養列的候選仍建立一筆「資料不足」結果，讓 LLM 知道它是比較選項之一。
            completed.append(
                DishNutrition(
                    dish_name=display_name,
                    matched_name=(
                        match_by_name.get(display_name, {}).get("matched_dish_name")
                        or match_by_name.get(display_name, {}).get("matched_food_name")
                    ),
                    matched_type=(
                        "dish"
                        if match_by_name.get(display_name, {}).get("matched_dish_name")
                        else "food_item"
                        if match_by_name.get(display_name, {}).get("matched_food_name")
                        else None
                    ),
                    match_score=match_by_name.get(display_name, {}).get("match_score"),
                    match_reason=match_by_name.get(display_name, {}).get("match_reason"),
                    retrieval_strategy=strategy_by_name.get(display_name, "not_found"),
                    nutrients=[
                        NutrientAmount(
                            name="熱量",
                            amount_per_serving=None,
                            unit="kcal",
                            calculation_method="macro_calculation",
                            formula="protein_g*4 + carbohydrate_g*4 + fat_g*9",
                            calorie_status="insufficient_macros",
                        ),
                        NutrientAmount(name="蛋白質", amount_per_serving=None, unit="g"),
                        NutrientAmount(name="脂肪", amount_per_serving=None, unit="g"),
                        NutrientAmount(name="碳水化合物", amount_per_serving=None, unit="g"),
                        NutrientAmount(name="糖", amount_per_serving=None, unit="g"),
                        NutrientAmount(name="鈉", amount_per_serving=None, unit="mg"),
                        NutrientAmount(name="膳食纖維", amount_per_serving=None, unit="g"),
                        NutrientAmount(name="飽和脂肪", amount_per_serving=None, unit="g"),
                    ],
                )
            )
        return completed
