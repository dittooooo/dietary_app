from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict


CURRENT_DIR = Path(__file__).resolve().parent
WORKSPACE_DIR = CURRENT_DIR.parents[2]
if str(WORKSPACE_DIR) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_DIR))

from neo4j import GraphDatabase

from src.nutritionist_agent.config import NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER
from src.nutritionist_agent.nutrition_calculator import NutritionCalculator
from src.nutritionist_agent.text_to_cypher import build_graph_retrieval_cypher


TARGET_NUTRIENTS = ["熱量", "蛋白質", "脂肪", "碳水化合物", "糖", "鈉"]
NUTRIENT_KEYS = {
    "熱量": "calories",
    "蛋白質": "protein_g",
    "脂肪": "fat_g",
    "碳水化合物": "carbohydrate_g",
    "糖": "sugar_g",
    "鈉": "sodium_mg",
    "calories": "calories",
    "protein": "protein_g",
    "fat": "fat_g",
    "carbohydrate": "carbohydrate_g",
    "carbs": "carbohydrate_g",
    "sugar": "sugar_g",
    "sodium": "sodium_mg",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--recipe-id", default="c0001")
    args = parser.parse_args()

    driver = GraphDatabase.driver(
        os.getenv("NEO4J_URI", NEO4J_URI),
        auth=(os.getenv("NEO4J_USER", NEO4J_USER), os.getenv("NEO4J_PASSWORD", NEO4J_PASSWORD)),
    )
    try:
        rows = fetch_rows(driver, args.recipe_id)
    finally:
        driver.close()

    print(json.dumps(build_trace(args.recipe_id, rows), ensure_ascii=False, indent=2))


def fetch_rows(driver: Any, recipe_id: str) -> list[dict[str, Any]]:
    with driver.session() as session:
        dish = session.run(
            "MATCH (d:Dish {recipe_id: $recipe_id}) "
            "RETURN d.name AS dish_name "
            "LIMIT 1",
            recipe_id=recipe_id,
        ).single()
    if not dish:
        return []

    dish_name = dish["dish_name"]
    query = build_graph_retrieval_cypher(
        [
            {
                "input_name": dish_name,
                "matched_dish_name": dish_name,
                "matched_food_id": None,
                "matched_food_name": None,
                "retrieval_strategy": "dish_match",
                "match_score": 100,
                "match_reason": "exact dish validation",
            }
        ],
        [],
    )
    with driver.session() as session:
        rows = session.run(query).data()
        ingredient_rows = session.run(
            """
            MATCH (d:Dish {recipe_id: $recipe_id})-[c:CONTAINS]->(ing:Ingredient)-[:MAPS_TO]->(f:FoodItem)
            RETURN c.order AS ingredient_order,
                   ing.name AS ingredient_name,
                   f.food_id AS food_id,
                   f.name AS food_name,
                   c.amount_raw AS amount_raw,
                   c.amount_value AS amount_value,
                   c.amount_unit AS amount_unit,
                   c.amount_per_serving AS ingredient_g
            ORDER BY ingredient_order, ingredient_name
            LIMIT 1000
            """,
            recipe_id=recipe_id,
        ).data()
    ingredient_index = {row["ingredient_name"]: row for row in ingredient_rows}
    for row in rows:
        row.update(ingredient_index.get(row.get("ingredient_name"), {}))
        row["recipe_id"] = recipe_id
    return rows


def build_trace(recipe_id: str, rows: list[dict[str, Any]]) -> Dict[str, Any]:
    if not rows:
        return {"recipe_id": recipe_id, "error": "No nutrition rows found."}

    dish_name = rows[0]["dish_name"]
    calculator = NutritionCalculator()
    summaries, debug_rows = calculator.summarize_and_recalculate(rows)
    ingredient_map: Dict[str, Dict[str, Any]] = {}
    totals: Dict[str, float] = defaultdict(float)
    raw_nutrition_totals: Dict[str, float] = defaultdict(float)

    for row in rows:
        ingredient_name = row["ingredient_name"]
        ingredient = ingredient_map.setdefault(
            ingredient_name,
            {
                "ingredient_order": row["ingredient_order"],
                "ingredient_name": ingredient_name,
                "food_id": row["food_id"],
                "food_name": row["food_name"],
                "amount_raw": row["amount_raw"],
                "amount_value": row["amount_value"],
                "amount_unit": row["amount_unit"],
                "ingredient_g": row["ingredient_g"],
                "nutrition_calculation": defaultdict(list),
            },
        )
        nutrient_name = row.get("nutrition_name_zh") or row.get("nutrition_name")
        raw_label = f"{row.get('nutrition_name')} / {row.get('nutrition_name_zh')}"
        if isinstance(row.get("amount_per_serving"), (int, float)):
            raw_nutrition_totals[raw_label] += float(row["amount_per_serving"])
        key = NUTRIENT_KEYS.get(str(nutrient_name)) or NUTRIENT_KEYS.get(str(row.get("nutrition_name")))
        if not key:
            continue

        amount_per_100g = row.get("amount_per_100g")
        ingredient_g = row.get("ingredient_g")
        amount_per_serving = row.get("amount_per_serving")
        ingredient["nutrition_calculation"][key].append({
            "nutrition_name": nutrient_name,
            "raw_nutrition_name": row.get("nutrition_name"),
            "raw_nutrition_name_zh": row.get("nutrition_name_zh"),
            "amount_per_100g": amount_per_100g,
            "unit": row.get("unit"),
            "formula": "amount_per_100g * ingredient_g / 100",
            "ingredient_g": ingredient_g,
            "amount_per_serving": amount_per_serving,
        })
        if isinstance(amount_per_serving, (int, float)):
            totals[key] += float(amount_per_serving)

    summary_totals = {}
    if summaries:
        for nutrient in summaries[0].nutrients:
            key = NUTRIENT_KEYS.get(nutrient.name)
            if key:
                summary_totals[key] = nutrient.amount_per_serving

    debug = debug_rows[0] if debug_rows else {}
    protein = float(debug.get("protein_g") or summary_totals.get("protein_g") or 0.0)
    carbohydrate = float(debug.get("carbohydrate_g") or summary_totals.get("carbohydrate_g") or 0.0)
    fat = float(debug.get("fat_g") or summary_totals.get("fat_g") or 0.0)
    calculated_calories = float(debug.get("calories_kcal") or protein * 4 + carbohydrate * 4 + fat * 9)
    calories = float(debug.get("graph_calories_kcal_reference") or summary_totals.get("calories") or 0.0)
    difference_percent = abs(calories - calculated_calories) / abs(calories) * 100 if calories else None

    return {
        "recipe_id": recipe_id,
        "dish_name": dish_name,
        "ingredients": sorted(ingredient_map.values(), key=lambda item: item.get("ingredient_order") or 0),
        "raw_row_totals_by_recognized_chinese_or_english_names": {key: round(value, 2) for key, value in totals.items()},
        "raw_nutrition_totals_by_name": {
            key: round(value, 2)
            for key, value in sorted(raw_nutrition_totals.items(), key=lambda item: item[0])
        },
        "nutrition_agent_summary_totals": summary_totals,
        "nutrition_agent_calorie_debug": debug,
        "macro_calorie_formula": "protein_g * 4 + carbohydrate_g * 4 + fat_g * 9",
        "macro_calorie_substitution": f"{protein:.6f} * 4 + {carbohydrate:.6f} * 4 + {fat:.6f} * 9",
        "calculated_calories": round(calculated_calories, 2),
        "calorie_difference_percent": round(difference_percent, 2) if difference_percent is not None else None,
    }


if __name__ == "__main__":
    main()
