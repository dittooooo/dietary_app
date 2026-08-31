from __future__ import annotations

import logging
from typing import Any, Dict, List

from .answer_generator import AnswerGenerator
from .config import DEFAULT_TOP_N_ROWS, NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER
from .dish_matcher import DishMatcher
from .models import (
    DishNutrition,
    DishNutritionRequest,
    DishNutritionResponse,
    HealthCondition,
    NutrientAmount,
    NutritionAgentRequest,
    NutritionAgentResponse,
    QuestionType,
    UserProfile,
)
from .nutrition_calculator import NutritionCalculator
from .retriever import GraphRetriever
from .text_to_cypher import (
    create_text_to_cypher_translator,
    normalize_request_payload,
)
from .cypher_guard import validate_nutrition_rows

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
        self.translator = create_text_to_cypher_translator()
        self.dish_matcher = DishMatcher(self.retriever.driver)
        self.nutrition_calculator = NutritionCalculator()
        self.answer_generator = AnswerGenerator()

    ###
    #  關閉 Neo4j 連線資源，通常用於服務關閉或測試清理。
    ###
    def close(self) -> None:
        self.retriever.close()

    ###
    #  查詢單一道料理的營養成分，提供飲食紀錄新增資料時使用，不產生 LLM 飲食建議。
    ###
    def get_dish_nutrition(self, request: DishNutritionRequest) -> DishNutritionResponse:
        # 這支 API 只接受純料理名稱；先 trim 避免空白字串進入圖譜查詢。
        dish_name = request.dish_name.strip()
        if not dish_name:
            raise ValueError("dish_name is required.")

        # 單一料理營養查詢不需要個人資料、慢性病與近期飲食；建立空模型只是為了共用 payload 格式。
        user_profile = UserProfile()
        health_condition = HealthCondition()
        weekly_records: List[Any] = []
        question_type: QuestionType = "single_dish"

        # 單一料理 endpoint 的輸入本身就是 authoritative dish candidate。
        dish_candidates = [dish_name]
        amount_by_dish = {dish_name: 1}
        logger.info("[NutritionAgent] nutrition_lookup_candidates=%s", dish_candidates)
        match_results = self._attach_amounts(
            self.dish_matcher.match_dishes(dish_candidates),
            amount_by_dish,
        )
        logger.info("[NutritionAgent] nutrition_lookup_match=%s", match_results)

        # 帶入配對結果，讓 TextToCypherTranslator 能依 retrieval_strategy 組查詢。
        full_payload = normalize_request_payload(
            question=dish_name,
            question_type=question_type,
            user_profile=user_profile,
            health_condition=health_condition,
            weekly_diet_records=weekly_records,
            dish_info_list=[{"dish_name": dish_name, "amount": 1}],
            dish_match_results=match_results,
        )
        translated = self.translator.translate_template(full_payload)

        # 執行 Neo4j 查詢後只取營養 rows，不進入 AnswerGenerator，因此不會打 OpenAI。
        rows = self._retrieve_translated_nutrition_rows(full_payload, translated)

        missing_candidates = self._missing_candidates_from_rows(dish_candidates, match_results, rows)
        if missing_candidates:
            # 若 Dish 配對有結果但查不到營養列，退回 ingredient_fallback 再查一次，增加飲食紀錄可用率。
            fallback_results = self._build_fallback_results(missing_candidates, {name: 1 for name in missing_candidates})
            fallback_payload = normalize_request_payload(
                question=dish_name,
                question_type=question_type,
                user_profile=user_profile,
                health_condition=health_condition,
                weekly_diet_records=weekly_records,
                dish_info_list=[
                    {"dish_name": name, "amount": amount_by_dish.get(name, 1)}
                    for name in missing_candidates
                ],
                dish_match_results=fallback_results,
            )
            fallback_rows = self._retrieve_template_nutrition_rows(fallback_payload)
            rows.extend(fallback_rows)
            logger.info(
                "[NutritionAgent] nutrition_lookup_fallback missing_candidates=%s fallback_row_count=%s",
                missing_candidates,
                len(fallback_rows),
            )

        # 把圖譜明細彙總成前端可存的主要營養素，熱量也會在這裡用三大營養素重算。
        dish_nutrition, nutrition_debug = self.nutrition_calculator.summarize_and_recalculate(rows)
        logger.info("[NutritionAgent] nutrition_lookup_debug=%s", nutrition_debug)
        if dish_nutrition:
            # 這支 API 只接受單一道料理，因此回傳第一筆營養摘要。
            return DishNutritionResponse(dish_nutrition=dish_nutrition[0])

        # 完全查不到營養資料時仍回傳固定格式，讓飲食紀錄端不用額外處理缺欄位。
        return DishNutritionResponse(
            dish_nutrition=self._empty_single_dish_nutrition(dish_name, dish_candidates, match_results)
        )

    ###
    # 執行完整問答生命週期，從 request 轉成圖譜資料，再產生飲食建議。
    ###
    def ask(self, request: NutritionAgentRequest) -> NutritionAgentResponse:
        logger.info("[NutritionAgent] start ask request=%s", request)
        
        # 請求中的個人資料都允許省略；缺少時用空模型，避免後續流程一直處理 None。
        user_profile = request.user_profile or UserProfile()
        health_condition = request.health_condition or HealthCondition()
        weekly_records = request.weekly_diet_records or []
        effective_question_type = request.question_type
        dish_info_list = [item.model_dump() for item in request.dish_info_list]
        dish_candidates = [item["dish_name"] for item in dish_info_list]

        # 呼叫端已完成料理抽取；這裡只使用結構化 dish_info_list。
        full_payload = normalize_request_payload(
            question=request.question,
            question_type=effective_question_type,
            user_profile=user_profile,
            health_condition=health_condition,
            weekly_diet_records=weekly_records,
            dish_info_list=dish_info_list,
        )
        logger.info("[NutritionAgent] dish_candidates=%s", dish_candidates)

        # 先把使用者輸入的料理名稱對齊圖譜中的 Dish 或 FoodItem，決定後續檢索策略。
        amount_by_dish = {item["dish_name"]: item["amount"] for item in dish_info_list}
        match_results = self._attach_amounts(
            self.dish_matcher.match_dishes(dish_candidates),
            amount_by_dish,
        )
        logger.info("[NutritionAgent] dish_match=%s", match_results)

        full_payload["dish_match_results"] = match_results
        translated = self.translator.translate(full_payload)
        cypher = translated["cypher"]
        question_type = translated.get("question_type", effective_question_type)  # type: ignore[assignment]
        logger.info("[NutritionAgent] generated_cypher=%s", cypher)

        # 使用受保護的 read-only Cypher 查 Neo4j，回來的是尚未彙總的營養列資料。
        rows = self._retrieve_translated_nutrition_rows(full_payload, translated)
        missing_candidates = self._missing_candidates_from_rows(dish_candidates, match_results, rows)
        if missing_candidates:
            # 若料理配對成功但沒有查到營養列，改用食材 fallback 再查一次，盡量保留回覆能力。
            fallback_results = self._build_fallback_results(missing_candidates, amount_by_dish)
            fallback_payload = normalize_request_payload(
                question=request.question,
                question_type=effective_question_type,
                user_profile=user_profile,
                health_condition=health_condition,
                weekly_diet_records=weekly_records,
                dish_info_list=[
                    {"dish_name": name, "amount": amount_by_dish.get(name, 1)}
                    for name in missing_candidates
                ],
                dish_match_results=fallback_results,
            )
            fallback_rows = self._retrieve_nutrition_rows(fallback_payload)
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

    ###
    # 找出候選料理中沒有從 Neo4j 查到任何營養資料的項目。
    ###
    def _retrieve_nutrition_rows(self, payload: Dict[str, Any]) -> List[Dict[str, Any]]:
        translated = self.translator.translate(payload)
        return self._retrieve_translated_nutrition_rows(payload, translated)

    @staticmethod
    def _attach_amounts(
        match_results: List[Dict[str, Any]],
        amount_by_dish: Dict[str, float],
    ) -> List[Dict[str, Any]]:
        return [
            {**result, "amount": amount_by_dish.get(str(result.get("input_name")), 1)}
            for result in match_results
        ]

    @staticmethod
    def _build_fallback_results(
        candidates: List[str],
        amount_by_dish: Dict[str, float],
    ) -> List[Dict[str, Any]]:
        return [
            {
                "input_name": candidate,
                "matched_dish_name": None,
                "match_score": 0,
                "match_reason": "no nutrition rows from dish match",
                "retrieval_strategy": "ingredient_fallback",
                "amount": amount_by_dish.get(candidate, 1),
            }
            for candidate in candidates
        ]

    def _retrieve_template_nutrition_rows(self, payload: Dict[str, Any]) -> List[Dict[str, Any]]:
        translated = self.translator.translate_template(payload)
        return self._retrieve_translated_nutrition_rows(payload, translated)

    def _retrieve_translated_nutrition_rows(
        self,
        payload: Dict[str, Any],
        translated: Dict[str, str],
    ) -> List[Dict[str, Any]]:
        try:
            rows = self.retriever.retrieve(translated["cypher"])
            validate_nutrition_rows(rows)
            if self._should_fallback_for_missed_exact_dishes(payload, translated, rows):
                raise ValueError("LangChain query did not return rows for exact dish matches.")
            return rows
        except Exception as exc:
            if not self.translator.should_fallback_on_retrieval_error(translated):
                raise
            logger.warning("[NutritionAgent] langchain cypher retrieval failed; falling back to template: %s", exc)
            template_translated = self.translator.translate_template(payload)
            rows = self.retriever.retrieve(template_translated["cypher"])
            validate_nutrition_rows(rows)
            return rows

    @staticmethod
    def _should_fallback_for_missed_exact_dishes(
        payload: Dict[str, Any],
        translated: Dict[str, str],
        rows: List[Dict[str, Any]],
    ) -> bool:
        if translated.get("cypher_mode") != "langchain":
            return False

        exact_targets = {
            str(item.get("input_name") or item.get("raw_input_name"))
            for item in payload.get("dish_match_results", [])
            if item.get("retrieval_strategy") == "dish_match"
        }
        exact_targets.update(
            {
                str(item.get("matched_dish_name"))
                for item in payload.get("dish_match_results", [])
                if item.get("retrieval_strategy") == "dish_match" and item.get("matched_dish_name")
            }
        )
        exact_targets.discard("")
        if not exact_targets:
            return False

        returned_names = {
            str(name)
            for row in rows
            for name in (row.get("dish_name"), row.get("matched_dish_name"), row.get("matched_name"))
            if name
        }
        return not exact_targets.issubset(returned_names)

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

    # 單一道料理查不到營養列時，回傳資料不足的固定營養欄位，讓呼叫端仍有穩定格式可存。
    @staticmethod
    def _empty_single_dish_nutrition(
        dish_name: str,
        dish_candidates: List[str],
        match_results: List[Dict[str, Any]],
    ) -> DishNutrition:
        # 優先使用清理後的候選名稱作為顯示名稱；若連候選都沒有，就回到原始輸入。
        display_name = dish_candidates[0] if dish_candidates else dish_name
        match = match_results[0] if match_results else {}
        return NutritionAgent._empty_nutrition(
            display_name,
            match,
        )

    @staticmethod
    def _empty_nutrition(dish_name: str, match: Dict[str, Any]) -> DishNutrition:
        return DishNutrition(
            dish_name=dish_name,
            matched_name=match.get("matched_dish_name") or match.get("matched_food_name"),
            matched_type=(
                "dish"
                if match.get("matched_dish_name")
                else "food_item"
                if match.get("matched_food_name")
                else None
            ),
            match_score=match.get("match_score"),
            match_reason=match.get("match_reason"),
            retrieval_strategy=match.get("retrieval_strategy") or "not_found",
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
                self._empty_nutrition(
                    display_name,
                    {
                        **match_by_name.get(display_name, {}),
                        "retrieval_strategy": strategy_by_name.get(display_name, "not_found"),
                    },
                )
            )
        return completed
