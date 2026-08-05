from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

try:
    from .knowledge_agent_importer import (
        BASE_DIR,
        FOOD_ALIAS_FIELD,
        FOOD_CATEGORY_FIELD,
        FOOD_ID_FIELD,
        FOOD_NAME_FIELD,
        NEO4J_PASSWORD,
        NEO4J_URI,
        NEO4J_USER,
        NUTRITION_DATA_PATH,
        VERSION,
        KnowledgeAgentImporter,
        batches,
        load_json,
        safe_float,
    )
except ImportError:
    from knowledge_agent_importer import (
        BASE_DIR,
        FOOD_ALIAS_FIELD,
        FOOD_CATEGORY_FIELD,
        FOOD_ID_FIELD,
        FOOD_NAME_FIELD,
        NEO4J_PASSWORD,
        NEO4J_URI,
        NEO4J_USER,
        NUTRITION_DATA_PATH,
        VERSION,
        KnowledgeAgentImporter,
        batches,
        load_json,
        safe_float,
    )


DEFAULT_NEW_MAPPING_PATH = (
    BASE_DIR
    / "data"
    / "recipe_and_nutrition"
    / "new_recipe_and_nutrition_mapping_v1.json"
)

APPEND_VERSION = f"{VERSION}_append_recipe_mapping_v1"


class AppendRecipeMappingImporter(KnowledgeAgentImporter):
    """Append recipes into the existing Neo4j graph without overwriting old data."""

    def import_mapping_file(self, mapping_path: Path, *, dry_run: bool = False) -> Dict[str, Any]:
        sources = self.load_sources()
        mapping_rows = load_json(mapping_path)
        if not isinstance(mapping_rows, list):
            raise ValueError(f"Mapping file must contain a JSON array: {mapping_path}")

        recipe_ids = [
            str(recipe.get("recipe_id") or "").strip()
            for recipe in mapping_rows
            if recipe.get("recipe_id")
        ]
        existing_recipe_ids = self._existing_recipe_ids(recipe_ids)
        rows = self._build_append_rows(mapping_rows, existing_recipe_ids)

        stats = {
            "mapping_path": str(mapping_path),
            "input_recipes": len(mapping_rows),
            "existing_recipes_skipped": len(existing_recipe_ids),
            "recipes_to_append": len(rows["recipe_rows"]),
            "ingredients_to_append": sum(len(row["ingredients"]) for row in rows["recipe_rows"]),
            "food_items_needed": len(rows["food_items"]),
            "food_nutrition_relationships_needed": len(rows["food_nutrition"]),
            "missing_food_ids": rows["missing_food_ids"],
            "dry_run": dry_run,
        }

        if dry_run:
            return stats

        self.create_schema()
        self._append_food_items(rows["food_items"], source=str(NUTRITION_DATA_PATH))
        self._append_food_nutrition(rows["food_nutrition"], source=str(NUTRITION_DATA_PATH))
        self._append_recipes(rows["recipe_rows"], source=str(mapping_path))
        return stats

    def _existing_recipe_ids(self, recipe_ids: List[str]) -> Set[str]:
        if not recipe_ids:
            return set()
        query = """
        MATCH (d:Dish)
        WHERE d.recipe_id IN $recipe_ids
        RETURN d.recipe_id AS recipe_id
        """
        with self.driver.session() as session:
            return {
                str(record["recipe_id"])
                for record in session.run(query, recipe_ids=recipe_ids)
                if record.get("recipe_id") is not None
            }

    def _build_append_rows(
        self,
        mapping_rows: List[Dict[str, Any]],
        existing_recipe_ids: Set[str],
    ) -> Dict[str, Any]:
        recipe_rows: List[Dict[str, Any]] = []
        missing_food_ids: List[Dict[str, str]] = []
        used_food_ids: Set[str] = set()

        for recipe in mapping_rows:
            recipe_id = str(recipe.get("recipe_id") or "").strip()
            recipe_name = str(recipe.get("recipe_name") or "").strip()
            if not recipe_id or not recipe_name or recipe_id in existing_recipe_ids:
                continue

            ingredients: List[Dict[str, Any]] = []
            for ing in recipe.get("resolved_ingredients", []):
                original = str(ing.get("original") or "").strip()
                matched = str(ing.get("matched") or "").strip()
                food_id = str(ing.get(FOOD_ID_FIELD) or "").strip()
                if not original:
                    continue

                food_row = self.food_by_id.get(food_id)
                if food_id and not food_row:
                    missing_food_ids.append(
                        {
                            "recipe_id": recipe_id,
                            "recipe_name": recipe_name,
                            "ingredient": original,
                            "food_id": food_id,
                        }
                    )

                ingredients.append(
                    {
                        "name": original,
                        "matched_food_id": food_id or None,
                        "matched_food_name": matched or None,
                        "amount_raw": ing.get("amount_raw"),
                        "amount_value": safe_float(ing.get("amount_value")),
                        "amount_unit": ing.get("amount_unit"),
                        "amount_note": ing.get("amount_note"),
                        "amount_per_serving": safe_float(ing.get("amount_per_serving")),
                        "mapping_method": ing.get("method"),
                    }
                )

                if not food_row:
                    continue

                used_food_ids.add(food_id)

            recipe_rows.append(
                {
                    "recipe_id": recipe_id,
                    "name": recipe_name,
                    "servings": recipe.get("servings"),
                    "ingredients": ingredients,
                }
            )

        food_items: List[Dict[str, Any]] = []
        food_nutrition: List[Dict[str, Any]] = []
        for food_id in sorted(used_food_ids):
            food_row = self.food_by_id.get(food_id)
            if not food_row:
                continue
            food_items.append(
                {
                    "food_id": food_id,
                    "name": food_row.get(FOOD_NAME_FIELD),
                    "category": food_row.get(FOOD_CATEGORY_FIELD),
                    "description": food_row.get("內容物描述"),
                    "aliases": food_row.get(FOOD_ALIAS_FIELD),
                }
            )
            for source_column, nutrient in self.nutrient_by_column.items():
                amount = safe_float(food_row.get(source_column))
                if amount is None:
                    continue
                food_nutrition.append(
                    {
                        "food_id": food_id,
                        "nutrition_id": nutrient["nutrition_id"],
                        "amount_per_100g": amount,
                        "unit": nutrient.get("unit"),
                        "source_column": source_column,
                    }
                )

        return {
            "recipe_rows": recipe_rows,
            "food_items": food_items,
            "food_nutrition": food_nutrition,
            "missing_food_ids": missing_food_ids,
        }

    def _append_food_items(self, rows: List[Dict[str, Any]], *, source: str) -> None:
        query = """
        UNWIND $rows AS row
        MERGE (f:FoodItem {food_id: row.food_id})
        ON CREATE SET
            f.name = row.name,
            f.category = row.category,
            f.description = row.description,
            f.aliases = row.aliases,
            f.source = $source,
            f.created_by_version = $version
        """
        self._run_batches(query, rows, source=source, version=APPEND_VERSION)

    def _append_food_nutrition(self, rows: List[Dict[str, Any]], *, source: str) -> None:
        query = """
        UNWIND $rows AS row
        MATCH (f:FoodItem {food_id: row.food_id})
        MATCH (n:Nutrition {nutrition_id: row.nutrition_id})
        MERGE (f)-[r:HAS_NUTRITION]->(n)
        ON CREATE SET
            r.amount_per_100g = row.amount_per_100g,
            r.amount = row.amount_per_100g,
            r.unit = row.unit,
            r.source_column = row.source_column,
            r.source = $source,
            r.created_by_version = $version
        """
        self._run_batches(query, rows, source=source, version=APPEND_VERSION)

    def _append_recipes(self, rows: List[Dict[str, Any]], *, source: str) -> None:
        query = """
        UNWIND $rows AS row
        MERGE (d:Dish {recipe_id: row.recipe_id})
        ON CREATE SET
            d.name = row.name,
            d.servings = row.servings,
            d.source = $source,
            d.created_by_version = $version
        WITH d, row
        UNWIND row.ingredients AS ing
        MERGE (i:Ingredient {name: ing.name})
        ON CREATE SET
            i.matched_food_id = ing.matched_food_id,
            i.matched_food_name = ing.matched_food_name,
            i.mapping_method = ing.mapping_method,
            i.created_by_version = $version
        MERGE (d)-[c:CONTAINS]->(i)
        ON CREATE SET
            c.amount_raw = ing.amount_raw,
            c.amount = ing.amount_value,
            c.unit = ing.amount_unit,
            c.amount_note = ing.amount_note,
            c.amount_per_serving = ing.amount_per_serving,
            c.matched_food_id = ing.matched_food_id,
            c.matched_food_name = ing.matched_food_name,
            c.mapping_method = ing.mapping_method,
            c.source = $source,
            c.created_by_version = $version
        WITH i, ing
        MATCH (f:FoodItem {food_id: ing.matched_food_id})
        MERGE (i)-[m:MAPS_TO]->(f)
        ON CREATE SET
            m.method = ing.mapping_method,
            m.source = $source,
            m.created_by_version = $version
        """
        self._run_batches(query, rows, source=source, version=APPEND_VERSION)

    def _run_batches(self, query: str, rows: List[Dict[str, Any]], **params: Any) -> None:
        if not rows:
            return
        with self.driver.session() as session:
            for chunk in batches(rows):
                session.run(query, rows=chunk, **params).consume()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Append recipe-nutrition mapping data into the existing Neo4j graph."
    )
    parser.add_argument(
        "--mapping-path",
        type=Path,
        default=DEFAULT_NEW_MAPPING_PATH,
        help="Path to the new recipe mapping JSON file.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and summarize rows without writing to Neo4j.",
    )
    args = parser.parse_args()

    importer = AppendRecipeMappingImporter(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)
    try:
        stats = importer.import_mapping_file(args.mapping_path, dry_run=args.dry_run)
        print(json.dumps(stats, ensure_ascii=False, indent=2))
    finally:
        importer.close()


if __name__ == "__main__":
    main()
