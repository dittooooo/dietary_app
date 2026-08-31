from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List

from audit_recipe_quality import (
    BASE_DIR,
    NUTRIENT_KEYS,
    NUTRITION_DATA_PATH,
    THRESHOLDS,
    audit_recipe,
    build_similarity_map,
    food_ids_from_source,
    number,
    text,
)


DEFAULT_MAPPING_PATH = BASE_DIR / "data" / "recipe_and_nutrition" / "new_recipe_and_nutrition_mapping_v1.json"
DEFAULT_OUTPUT_DIR = BASE_DIR / "output" / "recipe_mapping_v1_audit"
COMPONENTS_PATH = BASE_DIR / "data" / "recipe_and_nutrition" / "nutrition_components.json"


def load_food_nutrients() -> Dict[str, List[Dict[str, Any]]]:
    categorized = json.loads(NUTRITION_DATA_PATH.read_text(encoding="utf-8"))
    components = json.loads(COMPONENTS_PATH.read_text(encoding="utf-8"))
    nutrient_defs = [item for item in components.get("nutrients", []) if item.get("source_column")]
    food_rows: Dict[str, Dict[str, Any]] = {}
    for rows in categorized.values():
        if not isinstance(rows, list):
            continue
        for row in rows:
            if not isinstance(row, dict):
                continue
            food_id = text(row.get("整合編號")).splitlines()[0].strip()
            if food_id and food_id not in food_rows:
                food_rows[food_id] = row

    result: Dict[str, List[Dict[str, Any]]] = {}
    for food_id, row in food_rows.items():
        nutrients = []
        for definition in nutrient_defs:
            value = number(row.get(definition["source_column"]))
            if value is None:
                continue
            nutrients.append(
                {
                    "nutrition_id": text(definition.get("nutrition_id")),
                    "name": text(definition.get("name_zh")),
                    "name_zh": text(definition.get("name_zh")),
                    "unit": text(definition.get("unit")),
                    "amount_per_100g": value,
                }
            )
        result[food_id] = nutrients
    return result


def load_mapping(path: Path, food_nutrients: Dict[str, List[Dict[str, Any]]]) -> List[Dict[str, Any]]:
    records = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(records, list):
        raise ValueError(f"Recipe mapping must be a JSON list: {path}")
    recipes = []
    for record in records:
        ingredients = []
        for item in record.get("resolved_ingredients", []) or []:
            food_id = text(item.get("整合編號"))
            ingredients.append(
                {
                    "ingredient_key": text(item.get("original")),
                    "original_name": text(item.get("original")),
                    "matched_food_id": food_id,
                    "food_id": food_id,
                    "matched_food_name": text(item.get("matched")),
                    "food_name": text(item.get("matched")),
                    "food_category": "",
                    "amount_raw": item.get("amount_raw"),
                    "amount": number(item.get("amount_value")),
                    "amount_value": number(item.get("amount_value")),
                    "amount_unit": item.get("amount_unit"),
                    "unit": item.get("amount_unit"),
                    "amount_note": item.get("amount_note"),
                    "amount_per_serving": number(item.get("amount_per_serving")),
                    "order": len(ingredients) + 1,
                }
            )
        recipes.append(
            {
                "recipe_id": text(record.get("recipe_id")),
                "recipe_name": text(record.get("recipe_name")),
                "servings": record.get("servings"),
                "ingredients": ingredients,
                "food_nutrients": food_nutrients,
            }
        )
    return recipes


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit a recipe mapping JSON against the nutrition source before import.")
    parser.add_argument("--mapping-path", type=Path, default=DEFAULT_MAPPING_PATH)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    args = parser.parse_args()

    food_nutrients = load_food_nutrients()
    recipes = load_mapping(args.mapping_path, food_nutrients)
    source_food_ids = food_ids_from_source(NUTRITION_DATA_PATH)
    similar = build_similarity_map(recipes)
    audit_rows = [audit_recipe(recipe, source_food_ids, similar) for recipe in recipes]

    ingredients = []
    nutrition_rows = []
    for recipe, audit in zip(recipes, audit_rows):
        for item in recipe["ingredients"]:
            food_id = text(item.get("food_id")) or text(item.get("matched_food_id"))
            amount = number(item.get("amount_per_serving")) or number(item.get("amount"))
            ingredients.append(
                {
                    "recipe_id": recipe["recipe_id"],
                    "recipe_name": recipe["recipe_name"],
                    "ingredient_name": text(item.get("original_name")) or text(item.get("matched_food_name")),
                    "matched_food_name": text(item.get("matched_food_name")),
                    "food_id": food_id,
                    "amount_g": amount,
                    "amount_unit": text(item.get("amount_unit") or item.get("unit")),
                    "source_id_exists": food_id in source_food_ids,
                }
            )
        nutrition_rows.append(
            {
                "recipe_id": recipe["recipe_id"],
                "recipe_name": recipe["recipe_name"],
                "total_ingredient_g": audit["total_ingredient_g"],
                **{key: audit[key] for key in NUTRIENT_KEYS},
            }
        )

    duplicate_ids = [recipe_id for recipe_id, count in Counter(recipe["recipe_id"] for recipe in recipes).items() if count > 1]
    summary = {
        "generated_at": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat(),
        "audit_scope": "recipe_mapping_file",
        "report_title": "v1 Mapping 外食料理食譜品質檢測報告",
        "report_subtitle": f"檢測來源：{args.mapping_path}；尚未寫入或修改 Neo4j。PASS / WARNING / FAIL 是資料品質篩檢結果，不是臨床診斷。",
        "recipe_source_path": str(args.mapping_path),
        "recipe_count": len(audit_rows),
        "ingredient_relation_count": len(ingredients),
        "source_food_id_count": len(source_food_ids),
        "fooditem_count_in_graph": len(food_nutrients),
        "status_counts": dict(Counter(row["status"] for row in audit_rows)),
        "duplicate_recipe_ids": duplicate_ids,
        "source_food_ids_missing_in_graph": sorted(source_food_ids - set(food_nutrients)),
        "graph_food_ids_not_in_source": sorted(set(food_nutrients) - source_food_ids),
        "thresholds": THRESHOLDS,
        "sources": [
            {"name": "recipe mapping v1", "path": str(args.mapping_path)},
            {"name": "nutrition_data_categorized.json", "path": str(NUTRITION_DATA_PATH)},
            {"name": "衛生福利部國民健康署：正確飲食習慣", "url": "https://www.hpa.gov.tw/Pages/Detail.aspx?nodeid=543&pid=8365&sid=718"},
            {"name": "衛生福利部國民健康署：外食中主食如何吃得更健康", "url": "https://www.hpa.gov.tw/Pages/Detail.aspx?nodeid=4560&pid=16720&sid=16717"},
        ],
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    payload = {"summary": summary, "recipes": audit_rows, "ingredients": ingredients, "nutrition": nutrition_rows}
    (args.output_dir / "recipe_mapping_v1_audit.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    (args.output_dir / "recipe_mapping_v1_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
