from __future__ import annotations

import argparse
import json
import os
import re
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Tuple

from neo4j import GraphDatabase

try:
    from .knowledge_agent_importer import load_env_files
except ImportError:
    from knowledge_agent_importer import load_env_files


BASE_DIR = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = BASE_DIR / "output" / "recipes_r_from_neo4j_deduplicated.json"


def clean_text(value: Any) -> str:
    return str(value or "").strip()


def clean_food_id(value: Any) -> str:
    value = clean_text(value)
    return value.splitlines()[0].strip() if value else ""


def clean_number(value: Any) -> Any:
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value
    try:
        number = float(value)
    except (TypeError, ValueError):
        return value
    return int(number) if number.is_integer() else number


def normalized_name(value: Any) -> str:
    return re.sub(r"\s+", "", clean_text(value)).casefold()


def ingredient_name(contains: Dict[str, Any], ingredient: Dict[str, Any], food: Dict[str, Any]) -> str:
    return (
        clean_text(contains.get("original_name"))
        or clean_text(ingredient.get("original_name"))
        or clean_text(ingredient.get("name"))
        or clean_text(contains.get("matched_food_name"))
        or clean_text(ingredient.get("matched_food_name"))
        or clean_text(food.get("name"))
    )


def ingredient_record(
    contains: Dict[str, Any],
    ingredient: Dict[str, Any],
    maps_to: Dict[str, Any],
    food: Dict[str, Any],
) -> Dict[str, Any]:
    original = ingredient_name(contains, ingredient, food)
    food_id = clean_food_id(
        contains.get("matched_food_id")
        or ingredient.get("matched_food_id")
        or maps_to.get("matched_food_id")
        or food.get("food_id")
    )
    matched = (
        clean_text(contains.get("matched_food_name"))
        or clean_text(ingredient.get("matched_food_name"))
        or clean_text(food.get("name"))
    )
    return {
        "original": original,
        "matched": matched,
        "整合編號": food_id,
        "method": (
            clean_text(contains.get("mapping_method"))
            or clean_text(ingredient.get("mapping_method"))
            or clean_text(maps_to.get("method"))
            or clean_text(maps_to.get("source"))
            or None
        ),
        "amount_raw": contains.get("amount_raw"),
        "amount_value": clean_number(contains.get("amount_value", contains.get("amount"))),
        "amount_unit": contains.get("amount_unit", contains.get("unit")),
        "amount_note": contains.get("amount_note"),
        "amount_per_serving": clean_number(contains.get("amount_per_serving")),
    }


def completeness_score(contains: Dict[str, Any], ingredient: Dict[str, Any], food: Dict[str, Any]) -> int:
    values = [
        contains.get("amount_raw"),
        contains.get("amount_value", contains.get("amount")),
        contains.get("amount_unit", contains.get("unit")),
        contains.get("amount_per_serving"),
        contains.get("original_name") or ingredient.get("original_name") or ingredient.get("name"),
        contains.get("matched_food_id") or ingredient.get("matched_food_id") or food.get("food_id"),
    ]
    return sum(value not in (None, "") for value in values)


def row_sort_key(row: Dict[str, Any]) -> Tuple[int, int, str]:
    contains = row["contains"]
    order = contains.get("order")
    try:
        order_value = int(order)
    except (TypeError, ValueError):
        order_value = 2_147_483_647
    return (order_value, -completeness_score(row["contains"], row["ingredient"], row["food"]), row["name"])


def export_mapping(uri: str, user: str, password: str, prefix: str) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    query = """
    MATCH (d:Dish)
    WHERE d.recipe_id STARTS WITH $prefix
    OPTIONAL MATCH (d)-[c:CONTAINS]->(i:Ingredient)
    OPTIONAL MATCH (i)-[m:MAPS_TO]->(f:FoodItem)
    RETURN d.recipe_id AS recipe_id,
           d.name AS recipe_name,
           d.servings AS servings,
           properties(c) AS contains,
           properties(i) AS ingredient,
           properties(m) AS maps_to,
           properties(f) AS food
    ORDER BY recipe_id, coalesce(c.order, 2147483647), coalesce(i.name, '')
    """

    with GraphDatabase.driver(uri, auth=(user, password)) as driver:
        driver.verify_connectivity()
        rows = driver.execute_query(query, prefix=prefix, database_=None).records

    grouped: Dict[str, Dict[str, Any]] = {}
    raw_ingredient_rows = 0
    duplicate_rows_removed = 0
    duplicate_recipe_count = 0

    for result in rows:
        recipe_id = clean_text(result.get("recipe_id"))
        if not recipe_id:
            continue
        recipe = grouped.setdefault(
            recipe_id,
            {
                "recipe_id": recipe_id,
                "recipe_name": clean_text(result.get("recipe_name")),
                "servings": result.get("servings"),
                "rows": [],
            },
        )
        contains = result.get("contains") or {}
        ingredient = result.get("ingredient") or {}
        maps_to = result.get("maps_to") or {}
        food = result.get("food") or {}
        if not ingredient and not contains:
            continue
        raw_ingredient_rows += 1
        name = ingredient_name(contains, ingredient, food)
        if not name:
            continue
        recipe["rows"].append(
            {
                "name": name,
                "contains": contains,
                "ingredient": ingredient,
                "maps_to": maps_to,
                "food": food,
            }
        )

    output: List[Dict[str, Any]] = []
    for recipe_id in sorted(grouped):
        recipe = grouped[recipe_id]
        by_name: Dict[str, List[Dict[str, Any]]] = {}
        for row in recipe["rows"]:
            by_name.setdefault(normalized_name(row["name"]), []).append(row)

        selected: List[Dict[str, Any]] = []
        recipe_duplicate_count = 0
        for candidates in by_name.values():
            candidates.sort(key=row_sort_key)
            selected.append(candidates[0])
            recipe_duplicate_count += max(0, len(candidates) - 1)

        if recipe_duplicate_count:
            duplicate_recipe_count += 1
            duplicate_rows_removed += recipe_duplicate_count

        selected.sort(key=row_sort_key)
        output.append(
            {
                "recipe_id": recipe["recipe_id"],
                "recipe_name": recipe["recipe_name"],
                "resolved_ingredients": [
                    ingredient_record(row["contains"], row["ingredient"], row["maps_to"], row["food"])
                    for row in selected
                ],
                "servings": recipe["servings"],
            }
        )

    report = {
        "recipe_count": len(output),
        "raw_ingredient_rows": raw_ingredient_rows,
        "output_ingredient_rows": sum(len(row["resolved_ingredients"]) for row in output),
        "recipes_with_duplicate_ingredient_names": duplicate_recipe_count,
        "duplicate_ingredient_rows_removed": duplicate_rows_removed,
        "recipe_ids_prefix": prefix,
    }
    return output, report


def main() -> None:
    load_env_files()
    parser = argparse.ArgumentParser(description="Export r-prefixed Neo4j Dish data as v1 recipe mapping JSON.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--prefix", default="r")
    parser.add_argument("--uri", default=os.getenv("NEO4J_URI", "bolt://localhost:7687"))
    parser.add_argument("--user", default=os.getenv("NEO4J_USER", "neo4j"))
    parser.add_argument("--password", default=os.getenv("NEO4J_PASSWORD", "password"))
    args = parser.parse_args()

    records, report = export_mapping(args.uri, args.user, args.password, args.prefix)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")

    report["duplicate_names_remaining"] = 0
    for recipe in records:
        duplicate_name_check = Counter(
            normalized_name(item["original"])
            for item in recipe["resolved_ingredients"]
            if normalized_name(item["original"])
        )
        report["duplicate_names_remaining"] += sum(
            count - 1 for count in duplicate_name_check.values() if count > 1
        )
    report["output"] = str(args.output)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
