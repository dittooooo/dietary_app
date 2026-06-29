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
except ImportError:  # pragma: no cover - allows direct script execution
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
    / "recipes"
    / "new_recipe_and_nutrition_mapping_restaurant_tku_20260609.json"
)

IMPORT_VERSION = f"{VERSION}_restaurant_recipe_upsert_by_name_v1"

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


class RecipeMappingUpserter(KnowledgeAgentImporter):
    """Upsert restaurant recipes by dish name and rebuild their ingredients."""

    def import_mapping_file(self, mapping_path: Path, dry_run: bool = False) -> Dict[str, Any]:
        mapping_data = load_json(mapping_path)
        if not isinstance(mapping_data, list):
            raise ValueError(f"Expected a JSON list in {mapping_path}")

        original_count = len(mapping_data)
        mapping_data, duplicate_names, duplicate_recipe_ids = self._deduplicate_mapping(mapping_data)

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
            "input_recipes": original_count,
            "recipes_after_name_deduplication": len(rows),
            "duplicate_names_collapsed": duplicate_names,
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
            stats.update(self.verify_recipe_ids())
            stats["status"] = "dry_run_ok"
            return stats

        self._upsert_food_items(used_food_ids)
        self._upsert_food_nutrition(used_food_ids)
        self._upsert_recipes_by_name(rows)
        stats.update(self.verify_recipe_ids())
        stats["status"] = "imported"
        return stats

    def verify_recipe_ids(self) -> Dict[str, Any]:
        duplicate_query = """
        MATCH (dish:Dish)
        WHERE dish.recipe_id IS NOT NULL
        WITH dish.recipe_id AS recipe_id, count(*) AS count
        WHERE count > 1
        RETURN recipe_id, count
        ORDER BY count DESC, recipe_id
        """
        imported_count_query = """
        MATCH (dish:Dish)
        WHERE dish.version = $version
        RETURN count(dish) AS count
        """
        imported_contains_query = """
        MATCH (dish:Dish)-[r:CONTAINS]->(:Ingredient)
        WHERE dish.version = $version
        RETURN count(r) AS count
        """
        total_dish_query = """
        MATCH (dish:Dish)
        RETURN count(dish) AS count
        """
        dish_versions_query = """
        MATCH (dish:Dish)
        RETURN coalesce(dish.version, '<no version>') AS version, count(dish) AS count
        ORDER BY count DESC, version
        LIMIT 20
        """
        dish_sources_query = """
        MATCH (dish:Dish)
        RETURN coalesce(dish.source, '<no source>') AS source, count(dish) AS count
        ORDER BY count DESC, source
        LIMIT 20
        """
        with self.driver.session() as session:
            duplicate_recipe_ids = session.execute_read(
                lambda tx: [dict(record) for record in tx.run(duplicate_query)]
            )
            total_dishes = session.execute_read(
                lambda tx: tx.run(total_dish_query).single()["count"]
            )
            imported_dishes = session.execute_read(
                lambda tx: tx.run(imported_count_query, version=IMPORT_VERSION).single()["count"]
            )
            imported_contains = session.execute_read(
                lambda tx: tx.run(imported_contains_query, version=IMPORT_VERSION).single()["count"]
            )
            dish_versions = session.execute_read(
                lambda tx: [dict(record) for record in tx.run(dish_versions_query)]
            )
            dish_sources = session.execute_read(
                lambda tx: [dict(record) for record in tx.run(dish_sources_query)]
            )
        return {
            "neo4j_duplicate_recipe_ids": duplicate_recipe_ids,
            "neo4j_total_dishes": total_dishes,
            "neo4j_imported_version_dishes": imported_dishes,
            "neo4j_imported_version_contains_relationships": imported_contains,
            "neo4j_dish_versions_top20": dish_versions,
            "neo4j_dish_sources_top20": dish_sources,
        }

    def _reload_food_index_robustly(self) -> None:
        nutrition_data = load_json(NUTRITION_DATA_PATH)
        rows = [
            row
            for category in nutrition_data.values()
            for row in category
            if isinstance(row, dict)
        ]
        self.food_by_id = {}
        for row in rows:
            food_id = clean_text(first_value(row, FOOD_ID_KEYS))
            if food_id:
                self.food_by_id[food_id] = row

    def _deduplicate_mapping(self, mapping_data: List[Dict[str, Any]]) -> tuple[List[Dict[str, Any]], int, int]:
        by_name: Dict[str, Dict[str, Any]] = {}
        duplicate_names = 0
        for recipe in mapping_data:
            name = clean_text(recipe.get("recipe_name"))
            if not name:
                continue
            if name in by_name:
                duplicate_names += 1
            by_name[name] = recipe

        by_recipe_id: Dict[str, Dict[str, Any]] = {}
        duplicate_recipe_ids = 0
        for recipe in by_name.values():
            recipe_id = clean_text(recipe.get("recipe_id"))
            if recipe_id:
                if recipe_id in by_recipe_id:
                    duplicate_recipe_ids += 1
                by_recipe_id[recipe_id] = recipe

        return list(by_recipe_id.values()), duplicate_names, duplicate_recipe_ids

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
                    "source_file": "new_recipe_and_nutrition_mapping_restaurant_tku_20260609.json",
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
            r.unit = row.unit,
            r.basis = 'per_100g',
            r.version = $version
        """
        with self.driver.session() as session:
            session.execute_write(lambda tx: tx.run(query, rows=rows, version=IMPORT_VERSION).consume())

    def _upsert_recipes_by_name(self, rows: List[Dict[str, Any]]) -> None:
        query = """
        UNWIND $rows AS row
        OPTIONAL MATCH (old:Dish)
        WHERE old.name = row.name OR old.recipe_id = row.recipe_id
        WITH row, collect(DISTINCT old) AS old_dishes
        FOREACH (old IN old_dishes | DETACH DELETE old)
        CREATE (d:Dish {recipe_id: row.recipe_id})
        SET d.name = row.name,
            d.servings = row.servings,
            d.ingredient_count = row.ingredient_count,
            d.source = 'restaurant_tku_recipe_mapping',
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
        SET m.match_type = 'recipe_mapping',
            m.source = 'restaurant_tku_recipe_mapping',
            m.version = row.version
        """
        with self.driver.session() as session:
            session.execute_write(lambda tx: tx.run(query, rows=rows).consume())


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Upsert restaurant recipe mapping into Neo4j by recipe name."
    )
    parser.add_argument("--mapping-path", type=Path, default=DEFAULT_MAPPING_PATH)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    importer = RecipeMappingUpserter(
        os.getenv("NEO4J_URI", "bolt://localhost:7687"),
        os.getenv("NEO4J_USER", "neo4j"),
        os.getenv("NEO4J_PASSWORD", "password"),
    )
    try:
        if args.verify_only:
            stats = importer.verify_recipe_ids()
        else:
            stats = importer.import_mapping_file(args.mapping_path, dry_run=args.dry_run)
    finally:
        importer.close()
    print(json.dumps(stats, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
