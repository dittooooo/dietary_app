from __future__ import annotations

import json
from typing import Any, Dict, List

from .config import GRAPH_QUERY_LIMIT
from .cypher_guard import validate_nutrition_return_schema


SUMMARY_NUTRIENT_NAMES = [
    "熱量",
    "修正熱量",
    "粗蛋白",
    "蛋白質",
    "粗脂肪",
    "脂質",
    "脂肪",
    "總碳水化合物",
    "碳水化合物",
    "糖質總量",
    "糖",
    "鈉",
    "膳食纖維",
    "飽和脂肪",
]


def build_graph_retrieval_cypher(match_results: List[Dict[str, Any]]) -> str:
    """Build the single deterministic read-only nutrition query."""
    targets = [
        {
            "input_name": item["input_name"],
            "matched_dish_name": item["matched_dish_name"],
            "matched_food_id": item.get("matched_food_id"),
            "matched_food_name": item.get("matched_food_name"),
            "amount": item.get("amount", 1),
            "retrieval_strategy": item["retrieval_strategy"],
            "match_score": item.get("match_score"),
            "match_reason": item.get("match_reason"),
        }
        for item in match_results
        if item.get("retrieval_strategy") in {"dish_match", "ingredient_fallback", "fooditem_fallback"}
    ]
    if not targets:
        raise ValueError("No dish candidates are available for graph retrieval.")

    summary_nutrient_literal = json.dumps(SUMMARY_NUTRIENT_NAMES, ensure_ascii=False)
    total_limit = max(GRAPH_QUERY_LIMIT, GRAPH_QUERY_LIMIT * len(targets))
    cypher = f"""
UNWIND {cypher_literal(targets)} AS target
OPTIONAL MATCH (d:Dish)-[c:CONTAINS]->(dish_ing:Ingredient)
WHERE target.retrieval_strategy = "dish_match"
  AND d.name = target.matched_dish_name
OPTIONAL MATCH (fallback_ing:Ingredient)
WHERE target.retrieval_strategy = "ingredient_fallback"
  AND (target.input_name CONTAINS fallback_ing.name OR fallback_ing.name CONTAINS target.input_name)
OPTIONAL MATCH (fallback_food:FoodItem {{food_id: target.matched_food_id}})
WHERE target.retrieval_strategy = "fooditem_fallback"
WITH target, d, c, coalesce(dish_ing, fallback_ing) AS ing, fallback_food
WHERE ing IS NOT NULL OR fallback_food IS NOT NULL
OPTIONAL MATCH (ing)-[:MAPS_TO]->(mapped_food:FoodItem)
WITH target, d, c, ing, coalesce(fallback_food, mapped_food) AS f
WHERE f IS NOT NULL
  AND (fallback_food IS NOT NULL OR c IS NULL OR c.matched_food_id IS NULL OR f.food_id = c.matched_food_id)
MATCH (f)-[hn:HAS_NUTRITION]->(n:Nutrition)
WITH target, d, c, ing, f, hn, n,
  CASE
    WHEN c.amount_per_serving IS NOT NULL THEN round(hn.amount_per_100g * c.amount_per_serving * target.amount / 100.0, 6)
    ELSE round(hn.amount_per_100g * target.amount, 6)
  END AS amount_per_serving
WHERE amount_per_serving <> 0 OR n.name IN {summary_nutrient_literal} OR n.name_zh IN {summary_nutrient_literal}
WITH target, d, ing, f, hn, n, amount_per_serving
ORDER BY target.input_name, target.retrieval_strategy, ing.name, n.name
WITH target, collect({{
  dish_name: target.input_name,
  matched_name: CASE
    WHEN d.name IS NOT NULL THEN d.name
    WHEN target.retrieval_strategy = "fooditem_fallback" THEN f.name
    WHEN target.retrieval_strategy = "ingredient_fallback" THEN ing.name
    ELSE target.input_name
  END,
  matched_type: CASE
    WHEN d.name IS NOT NULL THEN "dish"
    WHEN target.retrieval_strategy = "fooditem_fallback" THEN "food_item"
    WHEN target.retrieval_strategy = "ingredient_fallback" THEN "ingredient"
    ELSE target.retrieval_strategy
  END,
  matched_dish_name: d.name,
  match_score: target.match_score,
  match_reason: target.match_reason,
  retrieval_strategy: target.retrieval_strategy,
  ingredient_name: ing.name,
  food_item_name: f.name,
  nutrition_name: n.name,
  nutrition_name_zh: n.name_zh,
  nutrition_category: n.category,
  amount_per_serving: amount_per_serving,
  amount_per_100g: hn.amount_per_100g,
  nutrition_unit: hn.unit,
  disease_name: null,
  diet_rule_relation: null,
  diet_rule_direction: null,
  diet_rule_note: null,
  diet_rule_reason: null,
  food_level_condition: null,
  sources_json: null
}})[..{GRAPH_QUERY_LIMIT}] AS limited_rows
UNWIND limited_rows AS row
RETURN
  row.dish_name AS dish_name,
  row.matched_name AS matched_name,
  row.matched_type AS matched_type,
  row.matched_dish_name AS matched_dish_name,
  row.match_score AS match_score,
  row.match_reason AS match_reason,
  row.retrieval_strategy AS retrieval_strategy,
  row.ingredient_name AS ingredient_name,
  row.food_item_name AS food_item_name,
  row.nutrition_name AS nutrition_name,
  row.nutrition_name_zh AS nutrition_name_zh,
  row.nutrition_category AS nutrition_category,
  row.amount_per_serving AS amount_per_serving,
  row.amount_per_100g AS amount_per_100g,
  row.nutrition_unit AS nutrition_unit,
  row.disease_name AS disease_name,
  row.diet_rule_relation AS diet_rule_relation,
  row.diet_rule_direction AS diet_rule_direction,
  row.diet_rule_note AS diet_rule_note,
  row.diet_rule_reason AS diet_rule_reason,
  row.food_level_condition AS food_level_condition,
  row.sources_json AS sources_json
ORDER BY dish_name, retrieval_strategy, ingredient_name, nutrition_name
LIMIT {total_limit}
""".strip()
    validate_nutrition_return_schema(cypher)
    return cypher


def cypher_literal(items: List[Dict[str, Any]]) -> str:
    chunks = []
    for item in items:
        props = [f"{key}: {json.dumps(value, ensure_ascii=False)}" for key, value in item.items()]
        chunks.append("{" + ", ".join(props) + "}")
    return "[" + ", ".join(chunks) + "]"
