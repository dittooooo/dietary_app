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
    CalorieEstimate, DishInfo, DishNutrition, DishNutritionRequest, DishNutritionResponse,
    DishSearchResponse, DishSearchResult,
    HealthCondition, NutrientAmount, NutritionAgentRequest, NutritionAgentResponse,
)
from .nutrition_calculator import COMMON_NUTRIENT_ALIASES, MACRO_FORMULA, NutritionCalculator, calculate_calories
from .retriever import GraphRetriever
from .template_cypher import SUMMARY_NUTRIENT_NAMES, build_graph_retrieval_cypher

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

    def search_dishes(self, query: str, *, limit: int = 20) -> DishSearchResponse:
        """Find Dish and FoodItem nodes whose names contain the supplied keyword."""
        query = query.strip()
        if not query:
            raise ValueError("q must not be blank")

        parameters = {"query": query, "limit": limit}
        count_rows = self.retriever.retrieve(
            """
            MATCH (n)
            WHERE (n:Dish OR n:FoodItem) AND n.name CONTAINS $query
            RETURN count(n) AS total
            LIMIT 1
            """,
            parameters,
        )
        rows = self.retriever.retrieve(
            """
            MATCH (n)
            WHERE (n:Dish OR n:FoodItem) AND n.name CONTAINS $query
            RETURN CASE WHEN n:Dish THEN n.recipe_id ELSE n.food_id END AS id,
                   n.name AS name,
                   CASE WHEN n:Dish THEN "dish" ELSE "food_item" END AS type
            ORDER BY CASE
                WHEN n.name = $query THEN 0
                WHEN n.name STARTS WITH $query THEN 1
                ELSE 2
            END, n.name, type
            LIMIT $limit
            """,
            parameters,
        )
        return DishSearchResponse(
            query=query,
            results=self._add_search_calories([DishSearchResult(**row) for row in rows]),
            total=int(count_rows[0]["total"]),
            limit=limit,
        )

    def _add_search_calories(self, results: List[DishSearchResult]) -> List[DishSearchResult]:
        if not results:
            return []

        rows = self.retriever.retrieve(
            """
            UNWIND $targets AS target
            OPTIONAL MATCH (f:FoodItem {food_id: target.id})-[fh:HAS_NUTRITION]->(fn:Nutrition)
            WHERE target.type = "food_item"
              AND coalesce(fn.name_zh, fn.name) IN $nutrient_names
            WITH target, collect(CASE WHEN fn IS NULL THEN null ELSE {
                name: coalesce(fn.name_zh, fn.name),
                amount: fh.amount_per_100g,
                unit: fh.unit
            } END) AS food_nutrients
            OPTIONAL MATCH (d:Dish {recipe_id: target.id})-[c:CONTAINS]->(:Ingredient)-[:MAPS_TO]->(df:FoodItem)-[dh:HAS_NUTRITION]->(dn:Nutrition)
            WHERE target.type = "dish"
              AND coalesce(dn.name_zh, dn.name) IN $nutrient_names
            WITH target, food_nutrients, collect(CASE WHEN dn IS NULL THEN null ELSE {
                name: coalesce(dn.name_zh, dn.name),
                amount: dh.amount_per_100g * c.amount_per_serving / 100.0,
                unit: dh.unit
            } END) AS dish_nutrients
            RETURN target.id AS id,
                   target.type AS type,
                   CASE WHEN target.type = "dish" THEN dish_nutrients ELSE food_nutrients END AS nutrients
            LIMIT $limit
            """,
            {
                "targets": [{"id": item.id, "type": item.type} for item in results],
                "nutrient_names": SUMMARY_NUTRIENT_NAMES,
                "limit": len(results),
            },
        )
        estimates = {
            (str(row["id"]), str(row["type"])): self._estimate_calories(row.get("nutrients") or [], str(row["type"]))
            for row in rows
        }
        return [item.model_copy(update={"calories": estimates.get((item.id, item.type))}) for item in results]

    @staticmethod
    def _estimate_calories(nutrients: List[Dict[str, Any]], item_type: str) -> CalorieEstimate | None:
        values: Dict[str, float] = {}
        graph_calories: float | None = None
        for nutrient in nutrients:
            raw_name = str(nutrient.get("name") or "")
            name = COMMON_NUTRIENT_ALIASES.get(raw_name, raw_name)
            amount = nutrient.get("amount")
            unit = str(nutrient.get("unit") or "").lower()
            if not isinstance(amount, (int, float)):
                continue
            if name in {"蛋白質", "碳水化合物", "脂肪"} and unit == "g":
                values[name] = values.get(name, 0.0) + float(amount)
            elif name == "熱量" and unit == "kcal":
                graph_calories = (graph_calories or 0.0) + float(amount)

        if {"蛋白質", "碳水化合物", "脂肪"}.issubset(values):
            calories = calculate_calories(values["蛋白質"], values["碳水化合物"], values["脂肪"])
        elif graph_calories is not None:
            calories = round(graph_calories, 2)
        else:
            return None

        return CalorieEstimate(
            value=calories,
            basis="per_serving" if item_type == "dish" else "per_100g",
        )

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
