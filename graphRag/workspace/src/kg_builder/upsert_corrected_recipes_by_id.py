from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any, Dict, List, Sequence

try:
    from .knowledge_agent_importer import (
        BASE_DIR,
        FOOD_ALIAS_FIELD,
        FOOD_CATEGORY_FIELD,
        FOOD_ID_FIELD,
        FOOD_NAME_FIELD,
        NUTRITION_DATA_PATH,
        VERSION,
        KnowledgeAgentImporter,
        load_json,
    )
except ImportError:  # pragma: no cover
    from knowledge_agent_importer import (
        BASE_DIR,
        FOOD_ALIAS_FIELD,
        FOOD_CATEGORY_FIELD,
        FOOD_ID_FIELD,
        FOOD_NAME_FIELD,
        NUTRITION_DATA_PATH,
        VERSION,
        KnowledgeAgentImporter,
        load_json,
    )


DEFAULT_MAPPING_PATH = (
    BASE_DIR
    / "src"
    / "nutrition_agent_v2"
    / "test_area"
    / "corrected_issue_recipes_match_reviewed.json"
)

IMPORT_VERSION = f"{VERSION}_corrected_issue_recipes_by_id_v1"

FOOD_ID_KEYS = ("整合編號", FOOD_ID_FIELD)
FOOD_NAME_KEYS = ("樣品名稱", FOOD_NAME_FIELD)
FOOD_CATEGORY_KEYS = ("食品分類", FOOD_CATEGORY_FIELD)
FOOD_ALIAS_KEYS = ("俗名", FOOD_ALIAS_FIELD)
FOOD_DESCRIPTION_KEYS = ("內容物描述",)


def first_value(row: Dict[str, Any], keys: Sequence[str]) -> Any:
    for key in keys:
        value = row.get(key)
        if value not in (None, ""):
            return value
    return None


def clean_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def get_float(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


class CorrectedRecipeByIdUpserter(KnowledgeAgentImporter):
    def import_mapping_file(self, mapping_path: Path, dry_run: bool = False) -> Dict[str, Any]:
        mapping_data = load_json(mapping_path)
        if not isinstance(mapping_data, list):
            raise ValueError(f"Expected a JSON list in {mapping_path}")

        mapping_data, duplicate_recipe_ids = self._deduplicate_by_recipe_id(mapping_data)

        self.create_schema()
        self.load_sources()
        self._reload_food_index_robustly()

        rows = self._build_recipe_rows(mapping_data)
        used_food_ids = {
            ingredient["matched_food_id"]
            for row in rows
            for ingredient in row["ingredients"]
            if ingredient.get("matched_food_id")
        }
        missing_food_ids = sorted(food_id for food_id in used_food_ids if food_id not in self.food_by_id)

        stats: Dict[str, Any] = {
            "mapping_file": str(mapping_path),
            "input_recipes": len(mapping_data) + duplicate_recipe_ids,
            "recipes_after_id_deduplication": len(rows),
            "duplicate_recipe_ids_collapsed": duplicate_recipe_ids,
            "ingredients": sum(len(row["ingredients"]) for row in rows),
            "food_items_needed": len(used_food_ids),
            "missing_food_ids": missing_food_ids,
            "dry_run": dry_run,
        }

        if missing_food_ids:
            stats["status"] = "blocked_missing_food_ids"
            return stats
        if dry_run:
            stats.update(self.verify_recipe_ids([row["recipe_id"] for row in rows]))
            stats["status"] = "dry_run_ok"
            return stats

        self._upsert_food_items(used_food_ids)
        self._upsert_food_nutrition(used_food_ids)
        self._upsert_recipes_by_id(rows)
        stats.update(self.verify_recipe_ids([row["recipe_id"] for row in rows]))
        stats["status"] = "imported"
        return stats

    def verify_recipe_ids(self, recipe_ids: List[str]) -> Dict[str, Any]:
        duplicate_query = """
        UNWIND $recipe_ids AS recipe_id
        MATCH (dish:Dish {recipe_id: recipe_id})
        WITH recipe_id, count(dish) AS count
        WHERE count > 1
        RETURN recipe_id, count
        ORDER BY count DESC, recipe_id
        """
        imported_count_query = """
        MATCH (dish:Dish)
        WHERE dish.recipe_id IN $recipe_ids AND dish.version = $version
        RETURN count(dish) AS count
        """
        untouched_count_query = """
        MATCH (dish:Dish)
        WHERE NOT dish.recipe_id IN $recipe_ids
        RETURN count(dish) AS count
        """
        contains_query = """
        MATCH (dish:Dish)-[r:CONTAINS]->(:Ingredient)
        WHERE dish.recipe_id IN $recipe_ids AND dish.version = $version
        RETURN count(r) AS count
        """
        with self.driver.session() as session:
            duplicates = session.execute_read(
                lambda tx: [dict(record) for record in tx.run(duplicate_query, recipe_ids=recipe_ids)]
            )
            imported_count = session.execute_read(
                lambda tx: tx.run(imported_count_query, recipe_ids=recipe_ids, version=IMPORT_VERSION).single()["count"]
            )
            untouched_count = session.execute_read(
                lambda tx: tx.run(untouched_count_query, recipe_ids=recipe_ids).single()["count"]
            )
            contains_count = session.execute_read(
                lambda tx: tx.run(contains_query, recipe_ids=recipe_ids, version=IMPORT_VERSION).single()["count"]
            )
        return {
            "neo4j_duplicate_recipe_ids_in_input_scope": duplicates,
            "neo4j_imported_scope_dishes": imported_count,
            "neo4j_imported_scope_contains_relationships": contains_count,
            "neo4j_dishes_outside_input_scope": untouched_count,
        }

    def _reload_food_index_robustly(self) -> None:
        nutrition_data = load_json(NUTRITION_DATA_PATH)
        rows = [row for category in nutrition_data.values() for row in category if isinstance(row, dict)]
        self.food_by_id = {}
        for row in rows:
            food_id = clean_text(first_value(row, FOOD_ID_KEYS))
            if food_id:
                self.food_by_id[food_id] = row

    def _deduplicate_by_recipe_id(self, mapping_data: List[Dict[str, Any]]) -> tuple[List[Dict[str, Any]], int]:
        by_id: Dict[str, Dict[str, Any]] = {}
        duplicates = 0
        for recipe in mapping_data:
            recipe_id = clean_text(recipe.get("recipe_id"))
            if not recipe_id:
                continue
            if recipe_id in by_id:
                duplicates += 1
            by_id[recipe_id] = recipe
        return list(by_id.values()), duplicates

    def _build_recipe_rows(self, mapping_data: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        rows: List[Dict[str, Any]] = []
        for recipe in mapping_data:
            recipe_id = clean_text(recipe.get("recipe_id"))
            recipe_name = clean_text(recipe.get("recipe_name"))
            if not recipe_id or not recipe_name:
                continue

            ingredients: List[Dict[str, Any]] = []
            for order, ingredient in enumerate(recipe.get("resolved_ingredients") or [], start=1):
                food_id = clean_text(first_value(ingredient, FOOD_ID_KEYS))
                name = clean_text(ingredient.get("matched") or ingredient.get("original"))
                if not food_id or not name:
                    continue
                ingredients.append(
                    {
                        "order": order,
                        "name": name,
                        "original": clean_text(ingredient.get("original")),
                        "matched_food_id": food_id,
                        "method": clean_text(ingredient.get("method")),
                        "amount_raw": clean_text(ingredient.get("amount_raw")),
                        "amount_value": get_float(ingredient.get("amount_value")),
                        "amount_unit": clean_text(ingredient.get("amount_unit")),
                        "amount_note": clean_text(ingredient.get("amount_note")),
                        "amount_per_serving": get_float(ingredient.get("amount_per_serving")),
                    }
                )

            rows.append(
                {
                    "recipe_id": recipe_id,
                    "name": recipe_name,
                    "servings": clean_text(recipe.get("servings") or "1"),
                    "ingredient_count": len(ingredients),
                    "ingredients": ingredients,
                    "source_file": mapping_data_source_name(),
                    "version": IMPORT_VERSION,
                }
            )
        return rows

    def _upsert_food_items(self, used_food_ids: set[str]) -> None:
        rows = []
        for food_id in sorted(used_food_ids):
            food = self.food_by_id[food_id]
            rows.append(
                {
                    "food_id": food_id,
                    "name": clean_text(first_value(food, FOOD_NAME_KEYS)) or food_id,
                    "category": clean_text(first_value(food, FOOD_CATEGORY_KEYS)),
                    "alias": clean_text(first_value(food, FOOD_ALIAS_KEYS)),
                    "description": clean_text(first_value(food, FOOD_DESCRIPTION_KEYS)),
                    "raw_json": json.dumps(food, ensure_ascii=False),
                }
            )

        query = """
        UNWIND $rows AS row
        MERGE (f:FoodItem {food_id: row.food_id})
        SET f.name = row.name,
            f.category = row.category,
            f.alias = row.alias,
            f.description = row.description,
            f.source = 'nutrition_data_categorized',
            f.version = $version,
            f.raw_json = row.raw_json
        """
        with self.driver.session() as session:
            session.execute_write(lambda tx: tx.run(query, rows=rows, version=IMPORT_VERSION).consume())

    def _upsert_food_nutrition(self, used_food_ids: set[str]) -> None:
        rows = []
        for food_id in sorted(used_food_ids):
            food = self.food_by_id[food_id]
            for nutrition_id, nutrient in self.nutrient_by_column.items():
                value = get_float(food.get(nutrient["source_column"]))
                if value is None:
                    continue
                rows.append(
                    {
                        "food_id": food_id,
                        "nutrition_id": nutrition_id,
                        "value": value,
                        "unit": clean_text(nutrient.get("unit")),
                    }
                )

        query = """
        UNWIND $rows AS row
        MATCH (f:FoodItem {food_id: row.food_id})
        MERGE (n:Nutrition {nutrition_id: row.nutrition_id})
        MERGE (f)-[r:HAS_NUTRITION]->(n)
        SET r.value_per_100g = row.value,
            r.amount_per_100g = row.value,
            r.unit = row.unit,
            r.basis = 'per_100g',
            r.version = $version
        """
        with self.driver.session() as session:
            session.execute_write(lambda tx: tx.run(query, rows=rows, version=IMPORT_VERSION).consume())

    def _upsert_recipes_by_id(self, rows: List[Dict[str, Any]]) -> None:
        query = """
        UNWIND $rows AS row
        OPTIONAL MATCH (old:Dish {recipe_id: row.recipe_id})
        FOREACH (dish IN CASE WHEN old IS NULL THEN [] ELSE [old] END | DETACH DELETE dish)
        CREATE (d:Dish {recipe_id: row.recipe_id})
        SET d.name = row.name,
            d.servings = row.servings,
            d.ingredient_count = row.ingredient_count,
            d.source = 'corrected_issue_recipe_mapping',
            d.source_file = row.source_file,
            d.version = row.version
        WITH d, row
        UNWIND row.ingredients AS ing
        MERGE (i:Ingredient {name: ing.name})
        SET i.original_name = ing.original,
            i.matched_food_id = ing.matched_food_id,
            i.last_recipe_import_version = row.version
        MERGE (d)-[c:CONTAINS]->(i)
        SET c.order = ing.order,
            c.original_name = ing.original,
            c.method = ing.method,
            c.amount_raw = ing.amount_raw,
            c.amount_value = ing.amount_value,
            c.amount_unit = ing.amount_unit,
            c.amount_note = ing.amount_note,
            c.amount_per_serving = ing.amount_per_serving,
            c.matched_food_id = ing.matched_food_id,
            c.version = row.version
        WITH i, ing, row
        MATCH (f:FoodItem {food_id: ing.matched_food_id})
        MERGE (i)-[m:MAPS_TO]->(f)
        SET m.match_type = 'corrected_recipe_mapping',
            m.source = 'corrected_issue_recipe_mapping',
            m.version = row.version
        """
        with self.driver.session() as session:
            session.execute_write(lambda tx: tx.run(query, rows=rows).consume())


def mapping_data_source_name() -> str:
    return "corrected_issue_recipes_match_reviewed.json"


def main() -> None:
    parser = argparse.ArgumentParser(description="Upsert corrected issue recipes into Neo4j by recipe_id only.")
    parser.add_argument("--mapping-path", type=Path, default=DEFAULT_MAPPING_PATH)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    importer = CorrectedRecipeByIdUpserter(
        os.getenv("NEO4J_URI", "bolt://localhost:7687"),
        os.getenv("NEO4J_USER", "neo4j"),
        os.getenv("NEO4J_PASSWORD", "password"),
    )
    try:
        stats = importer.import_mapping_file(args.mapping_path, dry_run=args.dry_run)
    finally:
        importer.close()
    print(json.dumps(stats, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
