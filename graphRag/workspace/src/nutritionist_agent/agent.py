from __future__ import annotations

import logging
from typing import Any, Dict, List

from .answer_generator import AnswerGenerator
from .config import NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER
from .cypher_guard import validate_nutrition_rows
from .disease_rules import retrieve_disease_rules
from .dish_matcher import DishMatcher, normalize_name
from .evidence_builder import UNITS, build_evidence
from .models import (
    DishInfo, DishNutrition, DishNutritionRequest, DishNutritionResponse,
    HealthCondition, NutrientAmount, NutritionAgentRequest, NutritionAgentResponse,
)
from .nutrition_calculator import MACRO_FORMULA, NutritionCalculator
from .retriever import GraphRetriever
from .template_cypher import build_graph_retrieval_cypher

logger = logging.getLogger(__name__)


class NutritionAgent:
    def __init__(self, *, neo4j_uri: str = NEO4J_URI, neo4j_user: str = NEO4J_USER,
                 neo4j_password: str = NEO4J_PASSWORD) -> None:
        self.retriever = GraphRetriever(neo4j_uri, neo4j_user, neo4j_password)
        self.dish_matcher = DishMatcher(self.retriever.driver)
        self.nutrition_calculator = NutritionCalculator()
        self.answer_generator = AnswerGenerator()

    def close(self) -> None:
        self.retriever.close()
        if self.answer_generator._client is not None:
            self.answer_generator._client.close()

    def get_dish_nutrition(self, request: DishNutritionRequest) -> DishNutritionResponse:
        dishes, _ = self._lookup(
            question=request.dish_name, question_type="single_dish",
            dish_info=[DishInfo(dish_name=request.dish_name)],
        )
        return DishNutritionResponse(dish_nutrition=dishes[0])

    def ask(self, request: NutritionAgentRequest) -> NutritionAgentResponse:
        from .models import UserProfile
        health = request.health_condition or HealthCondition()
        profile = request.user_profile or UserProfile()
        # Profile safety rules remain active; question mentions add discussion topics.
        rules = retrieve_disease_rules(self.retriever, health, request.question)
        dishes, rows = self._lookup(
            question=request.question, question_type=request.question_type,
            dish_info=request.dish_info_list,
        )
        evidence = build_evidence(profile, request.weekly_diet_records or [], dishes, rows, rules)
        evidence["disease_context"] = [
            {"name": group["requested"], "sources": group["context_sources"]}
            for group in rules
        ]
        logger.info("Evidence disease_status=%s rules_evaluated=%s preferred=%s",
                    evidence["disease_status"], evidence["rules_evaluated"], evidence["preferred_dish"])
        answer = self.answer_generator.generate(
            question=request.question, question_type=request.question_type,
            user_profile=profile, health_condition=health, dish_nutrition=dishes, evidence=evidence,
        )
        return NutritionAgentResponse(
            question=request.question, question_type=request.question_type, dish_nutrition=dishes,
            dish_advice=answer["dish_advice"], conclusion=answer["conclusion"],
        )

    def _lookup(self, *, question: str, question_type: str,
                dish_info: list[DishInfo]) -> tuple[list[DishNutrition], list[dict]]:
        # Matcher deduplicates normalized names; sum portions before matching so none are lost.
        inputs = {}
        for item in dish_info:
            key = normalize_name(item.dish_name)
            if key in inputs:
                inputs[key]["amount"] += item.amount
            else:
                inputs[key] = item.model_dump()
        if not inputs:
            raise ValueError("dish_info_list requires at least one dish.")
        info = list(inputs.values())
        amounts = {item["dish_name"]: item["amount"] for item in info}
        candidates = list(amounts)
        matches = [{**m, "amount": amounts[m["input_name"]]}
                   for m in self.dish_matcher.match_dishes(candidates)]
        # Rules are queried separately. Joining multiple diseases to nutrition would multiply totals.
        rows = self._retrieve_nutrition_rows(matches)
        missing = self._missing_candidates_from_rows(candidates, matches, rows)
        # A failed ingredient fallback must not repeat the identical query.
        retry = [m for m in matches if m["input_name"] in missing
                 and m["retrieval_strategy"] != "ingredient_fallback"]
        if retry:
            fallback = [{**m, "matched_dish_name": None, "matched_food_id": None,
                         "matched_food_name": None, "match_score": 0,
                         "match_reason": "no nutrition rows from dish match",
                         "retrieval_strategy": "ingredient_fallback"} for m in retry]
            rows.extend(self._retrieve_nutrition_rows(fallback))
        summaries, _ = self.nutrition_calculator.summarize_and_recalculate(rows)
        by_name = {d.dish_name: d for d in summaries}
        completed = [by_name[m["input_name"]] if m["input_name"] in by_name
                     else self._empty_nutrition(m["input_name"], m) for m in matches]
        return completed, rows

    def _retrieve_nutrition_rows(self, matches: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        rows = self.retriever.retrieve(build_graph_retrieval_cypher(matches))
        validate_nutrition_rows(rows)
        return rows

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
    def _empty_nutrition(dish_name: str, match: dict) -> DishNutrition:
        nutrients = [NutrientAmount(name=name, unit=unit) for name, unit in UNITS.items()]
        calories = next(n for n in nutrients if n.name == "熱量")
        calories.calculation_method = "macro_calculation"
        calories.formula = MACRO_FORMULA
        calories.calorie_status = "insufficient_macros"
        return DishNutrition(
            dish_name=dish_name,
            matched_name=match.get("matched_dish_name") or match.get("matched_food_name"),
            matched_type="dish" if match.get("matched_dish_name") else
                         "food_item" if match.get("matched_food_name") else None,
            match_score=match.get("match_score"), match_reason=match.get("match_reason"),
            retrieval_strategy=match.get("retrieval_strategy") or "not_found", nutrients=nutrients,
        )
