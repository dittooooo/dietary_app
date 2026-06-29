from __future__ import annotations

import logging
from typing import Any, Dict, List

from .answer_generator import AnswerGenerator
from .config import DEFAULT_TOP_N_ROWS, NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER
from .cypher_guard import validate_read_only_cypher
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


class NutritionAgent:
    def __init__(
        self,
        *,
        neo4j_uri: str = NEO4J_URI,
        neo4j_user: str = NEO4J_USER,
        neo4j_password: str = NEO4J_PASSWORD,
    ) -> None:
        self.retriever = GraphRetriever(neo4j_uri, neo4j_user, neo4j_password)
        self.translator = TextToCypherTranslator(self.retriever.driver)
        self.dish_matcher = DishMatcher(self.retriever.driver)
        self.nutrition_calculator = NutritionCalculator()
        self.answer_generator = AnswerGenerator()

    def close(self) -> None:
        self.retriever.close()

    def ask(self, request: NutritionAgentRequest) -> NutritionAgentResponse:
        user_profile = request.user_profile or UserProfile()
        health_condition = request.health_condition or HealthCondition()
        weekly_records = request.weekly_diet_records or []
        effective_question_type = infer_question_type(request.question, request.question_type)
        debug_trace: List[Dict[str, Any]] = []
        full_payload = normalize_request_payload(
            question=request.question,
            question_type=effective_question_type,
            user_profile=user_profile,
            health_condition=health_condition,
            weekly_diet_records=weekly_records,
        )
        self._trace(debug_trace, "normalize_request", "Normalized request payload for retrieval.", full_payload)

        if request.cypher:
            cypher = request.cypher
            validate_read_only_cypher(cypher)
            question_type = effective_question_type
            dish_candidates: List[str] = []
            match_results: List[Dict[str, Any]] = []
            self._trace(debug_trace, "input_cypher", "Using caller-provided read-only Cypher.", {"cypher": cypher})
        else:
            dish_candidates = extract_dish_candidates(full_payload)
            self._trace(
                debug_trace,
                "extract_dish_candidates",
                "Extracted dish candidates from question and structured fields.",
                dish_candidates,
            )
            match_results = self.dish_matcher.match_dishes(dish_candidates)
            self._trace(debug_trace, "dish_match", "Matched candidates against Dish nodes.", match_results)
            full_payload = normalize_request_payload(
                question=request.question,
                question_type=effective_question_type,
                user_profile=user_profile,
                health_condition=health_condition,
                weekly_diet_records=weekly_records,
                dish_candidates=dish_candidates,
                dish_match_results=match_results,
            )
            translated = self.translator.translate(full_payload)
            cypher = translated["cypher"]
            question_type = translated.get("question_type", effective_question_type)  # type: ignore[assignment]
            self._trace(
                debug_trace,
                "text_to_cypher",
                "Generated Cypher from full request payload.",
                {"cypher": cypher, "rationale": translated.get("rationale")},
            )

        rows = self.retriever.retrieve(cypher)
        fallback_cypher = None
        missing_candidates = self._missing_candidates_from_rows(dish_candidates, match_results, rows)
        if missing_candidates:
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
                dish_candidates=missing_candidates,
                dish_match_results=fallback_results,
            )
            translated_fallback = self.translator.translate(fallback_payload)
            fallback_cypher = translated_fallback["cypher"]
            fallback_rows = self.retriever.retrieve(fallback_cypher)
            rows.extend(fallback_rows)
            self._trace(
                debug_trace,
                "ingredient_fallback_retry",
                "Retried candidates with no dish nutrition rows using ingredient fallback.",
                {
                    "missing_candidates": missing_candidates,
                    "fallback_cypher": fallback_cypher,
                    "fallback_row_count": len(fallback_rows),
                },
            )
        self._trace(debug_trace, "graph_retrieval", "Retrieved graph rows from Neo4j.", {"row_count": len(rows)})
        dish_nutrition, nutrition_debug = self.nutrition_calculator.summarize_and_recalculate(rows)
        dish_nutrition = self._ensure_candidate_nutrition(
            dish_nutrition,
            dish_candidates,
            match_results,
            question_type,  # type: ignore[arg-type]
        )
        self._trace(
            debug_trace,
            "nutrition_calculation",
            "Summarized nutrition rows and recalculated calories from macros.",
            nutrition_debug,
        )
        answer_payload = self.answer_generator.generate(
            question=request.question,
            question_type=question_type,  # type: ignore[arg-type]
            user_profile=user_profile,
            health_condition=health_condition,
            weekly_diet_records=weekly_records,
            dish_nutrition=dish_nutrition,
            graph_rows=rows[:DEFAULT_TOP_N_ROWS],
            debug_trace=debug_trace if request.debug else None,
        )

        return NutritionAgentResponse(
            question=request.question,
            question_type=question_type,  # type: ignore[arg-type]
            dish_nutrition=dish_nutrition,
            dish_advice=answer_payload.get("dish_advice", []),
            conclusion=answer_payload.get("conclusion", ""),
            cypher_used=self._join_debug_cypher(cypher, fallback_cypher) if request.debug else None,
            graph_rows=rows if request.debug else None,
            debug_trace=debug_trace if request.debug else None,
        )

    @staticmethod
    def _trace(trace: List[Dict[str, Any]], step: str, message: str, data: Any) -> None:
        logger.info("[NutritionAgent] %s: %s", step, data)
        trace.append({"step": step, "message": message, "data": data})

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

    @staticmethod
    def _join_debug_cypher(primary_cypher: str, fallback_cypher: str | None) -> str:
        if not fallback_cypher:
            return primary_cypher
        return f"{primary_cypher}\n\n/* ingredient fallback retry */\n{fallback_cypher}"

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
