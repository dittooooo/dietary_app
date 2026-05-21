from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

from neo4j import GraphDatabase

try:
    from dotenv import dotenv_values
except ModuleNotFoundError:

    def dotenv_values(path: Path) -> Dict[str, Optional[str]]:
        values: Dict[str, Optional[str]] = {}
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
        return values


BASE_DIR = Path(__file__).resolve().parents[2]
DATA_DIR = BASE_DIR / "data"

FOOD_MAPPING_PATH = DATA_DIR / "recipe_and_nutrition" / "food_and_nutrition_mapping.json"
NUTRITION_DATA_PATH = DATA_DIR / "recipe_and_nutrition" / "nutrition_data_categorized.json"
NUTRITION_COMPONENTS_PATH = DATA_DIR / "recipe_and_nutrition" / "nutrition_components.json"
DISEASE_RULES_PATH = DATA_DIR / "disease_and_biomarker" / "chronic_disease_rules_v2.json"

VERSION = "knowledge_agent_importer_v1"
FOOD_ID_FIELD = "整合編號"
FOOD_NAME_FIELD = "樣品名稱"
FOOD_CATEGORY_FIELD = "食品分類"
FOOD_ALIAS_FIELD = "俗名"


def load_env_files() -> None:
    for env_path in [BASE_DIR / ".env", Path(__file__).resolve().parent / ".env"]:
        if not env_path.exists():
            continue
        for key, value in dotenv_values(env_path).items():
            if value is not None and os.getenv(key, "") in {"", "dummy-key"}:
                os.environ[key] = value


load_env_files()

NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")


def load_json(path: Path) -> Any:
    if not path.exists():
        raise FileNotFoundError(path)
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def safe_float(value: Any) -> Optional[float]:
    if value in {None, ""}:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def batches(items: List[Dict[str, Any]], size: int = 1000) -> Iterable[List[Dict[str, Any]]]:
    for index in range(0, len(items), size):
        yield items[index : index + size]


class KnowledgeAgentImporter:
    def __init__(self, uri: str, user: str, password: str) -> None:
        self.driver = GraphDatabase.driver(uri, auth=(user, password))
        self.nutrients: List[Dict[str, Any]] = []
        self.nutrient_by_column: Dict[str, Dict[str, Any]] = {}
        self.food_by_id: Dict[str, Dict[str, Any]] = {}

    def close(self) -> None:
        self.driver.close()

    def create_schema(self) -> None:
        queries = [
            "CREATE CONSTRAINT dish_recipe_id IF NOT EXISTS FOR (d:Dish) REQUIRE d.recipe_id IS UNIQUE",
            "CREATE CONSTRAINT ingredient_name IF NOT EXISTS FOR (i:Ingredient) REQUIRE i.name IS UNIQUE",
            "CREATE CONSTRAINT fooditem_food_id IF NOT EXISTS FOR (f:FoodItem) REQUIRE f.food_id IS UNIQUE",
            "CREATE CONSTRAINT nutrition_id IF NOT EXISTS FOR (n:Nutrition) REQUIRE n.nutrition_id IS UNIQUE",
            "CREATE CONSTRAINT disease_id IF NOT EXISTS FOR (d:Disease) REQUIRE d.disease_id IS UNIQUE",
            "CREATE INDEX dish_name IF NOT EXISTS FOR (d:Dish) ON (d.name)",
            "CREATE INDEX fooditem_name IF NOT EXISTS FOR (f:FoodItem) ON (f.name)",
            "CREATE INDEX nutrition_name IF NOT EXISTS FOR (n:Nutrition) ON (n.name)",
            "CREATE INDEX disease_name IF NOT EXISTS FOR (d:Disease) ON (d.name)",
        ]
        with self.driver.session() as session:
            for query in queries:
                session.run(query)

    def clear_graph(self) -> None:
        with self.driver.session() as session:
            session.run("MATCH (n) DETACH DELETE n")

    def load_sources(self) -> Dict[str, Any]:
        components = load_json(NUTRITION_COMPONENTS_PATH)
        self.nutrients = components.get("nutrients", [])
        self.nutrient_by_column = {
            nutrient["source_column"]: nutrient
            for nutrient in self.nutrients
            if nutrient.get("source_column")
        }

        nutrition_data = load_json(NUTRITION_DATA_PATH)
        food_rows: List[Dict[str, Any]] = []
        for category_rows in nutrition_data.values():
            if isinstance(category_rows, list):
                food_rows.extend(row for row in category_rows if isinstance(row, dict))

        self.food_by_id = {
            str(row.get(FOOD_ID_FIELD)).strip(): row
            for row in food_rows
            if row.get(FOOD_ID_FIELD)
        }

        return {
            "mapping": load_json(FOOD_MAPPING_PATH),
            "disease_rules": load_json(DISEASE_RULES_PATH),
            "food_rows": food_rows,
        }

    def import_nutrition_components(self) -> None:
        name_counts: Dict[str, int] = {}
        for nutrient in self.nutrients:
            name = str(nutrient.get("name_zh") or "").strip()
            if name:
                name_counts[name] = name_counts.get(name, 0) + 1

        rows = [
            {
                "nutrition_id": n.get("nutrition_id"),
                "name": self._nutrition_display_name(n, name_counts),
                "name_zh": n.get("name_zh"),
                "name_en": n.get("name_en"),
                "unit": n.get("unit"),
                "category": n.get("category"),
                "source_column": n.get("source_column"),
            }
            for n in self.nutrients
            if n.get("nutrition_id") and n.get("name_zh")
        ]
        query = """
        UNWIND $rows AS row
        MERGE (n:Nutrition {nutrition_id: row.nutrition_id})
        SET n.name = row.name,
            n.name_zh = row.name_zh,
            n.name_en = row.name_en,
            n.unit = row.unit,
            n.category = row.category,
            n.source_column = row.source_column,
            n.source = $source,
            n.updated_by_version = $version
        """
        self._run_batches(query, rows, source=str(NUTRITION_COMPONENTS_PATH), version=VERSION)

    def import_food_items_and_nutrition(self, food_rows: List[Dict[str, Any]]) -> None:
        food_items: List[Dict[str, Any]] = []
        food_nutrition: List[Dict[str, Any]] = []

        for row in food_rows:
            food_id = str(row.get(FOOD_ID_FIELD, "")).strip()
            food_name = str(row.get(FOOD_NAME_FIELD, "")).strip()
            if not food_id or not food_name:
                continue

            food_items.append(
                {
                    "food_id": food_id,
                    "name": food_name,
                    "category": row.get(FOOD_CATEGORY_FIELD),
                    "description": row.get("內容物描述"),
                    "aliases": row.get(FOOD_ALIAS_FIELD),
                }
            )

            for source_column, nutrient in self.nutrient_by_column.items():
                amount = safe_float(row.get(source_column))
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

        food_query = """
        UNWIND $rows AS row
        MERGE (f:FoodItem {food_id: row.food_id})
        SET f.name = row.name,
            f.category = row.category,
            f.description = row.description,
            f.aliases = row.aliases,
            f.source = $source,
            f.updated_by_version = $version
        """
        nutrition_query = """
        UNWIND $rows AS row
        MATCH (f:FoodItem {food_id: row.food_id})
        MATCH (n:Nutrition {nutrition_id: row.nutrition_id})
        MERGE (f)-[r:HAS_NUTRITION]->(n)
        SET r.amount_per_100g = row.amount_per_100g,
            r.amount = row.amount_per_100g,
            r.unit = row.unit,
            r.source_column = row.source_column,
            r.source = $source,
            r.updated_by_version = $version
        """
        self._run_batches(food_query, food_items, source=str(NUTRITION_DATA_PATH), version=VERSION)
        self._run_batches(nutrition_query, food_nutrition, source=str(NUTRITION_DATA_PATH), version=VERSION)

    def import_recipes_and_mappings(self, mapping_rows: List[Dict[str, Any]]) -> None:
        recipe_rows: List[Dict[str, Any]] = []
        ingredient_nutrition: List[Dict[str, Any]] = []

        for recipe in mapping_rows:
            recipe_id = recipe.get("recipe_id")
            recipe_name = recipe.get("recipe_name")
            if not recipe_id or not recipe_name:
                continue

            ingredients = []
            for ing in recipe.get("resolved_ingredients", []):
                original = str(ing.get("original") or "").strip()
                matched = str(ing.get("matched") or "").strip()
                food_id = str(ing.get(FOOD_ID_FIELD) or "").strip()
                if not original:
                    continue

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

                food_row = self.food_by_id.get(food_id)
                if not food_row:
                    continue
                grams_per_serving = safe_float(ing.get("amount_per_serving"))
                for source_column, nutrient in self.nutrient_by_column.items():
                    amount_per_100g = safe_float(food_row.get(source_column))
                    if amount_per_100g is None:
                        continue
                    amount_per_serving = None
                    if grams_per_serving is not None:
                        amount_per_serving = round(amount_per_100g * grams_per_serving / 100.0, 6)
                    ingredient_nutrition.append(
                        {
                            "ingredient_name": original,
                            "food_id": food_id,
                            "food_name": matched,
                            "nutrition_id": nutrient["nutrition_id"],
                            "amount_per_100g": amount_per_100g,
                            "amount_per_serving": amount_per_serving,
                            "unit": nutrient.get("unit"),
                            "source_column": source_column,
                        }
                    )

            recipe_rows.append(
                {
                    "recipe_id": recipe_id,
                    "name": recipe_name,
                    "servings": recipe.get("servings"),
                    "ingredients": ingredients,
                }
            )

        recipe_query = """
        UNWIND $rows AS row
        MERGE (d:Dish {recipe_id: row.recipe_id})
        SET d.name = row.name,
            d.servings = row.servings,
            d.source = $source,
            d.updated_by_version = $version
        WITH d, row
        UNWIND row.ingredients AS ing
        MERGE (i:Ingredient {name: ing.name})
        SET i.matched_food_id = ing.matched_food_id,
            i.matched_food_name = ing.matched_food_name,
            i.mapping_method = ing.mapping_method,
            i.updated_by_version = $version
        MERGE (d)-[c:CONTAINS]->(i)
        SET c.amount_raw = ing.amount_raw,
            c.amount = ing.amount_value,
            c.unit = ing.amount_unit,
            c.amount_note = ing.amount_note,
            c.amount_per_serving = ing.amount_per_serving,
            c.matched_food_id = ing.matched_food_id,
            c.matched_food_name = ing.matched_food_name,
            c.mapping_method = ing.mapping_method,
            c.source = $source
        WITH i, ing
        MATCH (f:FoodItem {food_id: ing.matched_food_id})
        MERGE (i)-[m:MAPS_TO]->(f)
        SET m.method = ing.mapping_method,
            m.source = $source,
            m.updated_by_version = $version
        """

        ingredient_nutrition_query = """
        UNWIND $rows AS row
        MATCH (i:Ingredient {name: row.ingredient_name})
        MATCH (n:Nutrition {nutrition_id: row.nutrition_id})
        MERGE (i)-[r:HAS_NUTRITION {food_id: row.food_id}]->(n)
        SET r.source_food_name = row.food_name,
            r.source_food_id = row.food_id,
            r.amount_per_100g = row.amount_per_100g,
            r.amount_per_serving = row.amount_per_serving,
            r.amount = row.amount_per_100g,
            r.unit = row.unit,
            r.source_column = row.source_column,
            r.source = $source,
            r.updated_by_version = $version
        """
        self._run_batches(recipe_query, recipe_rows, source=str(FOOD_MAPPING_PATH), version=VERSION)
        self._run_batches(ingredient_nutrition_query, ingredient_nutrition, source=str(FOOD_MAPPING_PATH), version=VERSION)

    def import_disease_rules(self, disease_rules: Dict[str, Any]) -> None:
        disease_rows: List[Dict[str, Any]] = []
        rule_rows: List[Dict[str, Any]] = []

        for disease in disease_rules.get("diseases", []):
            disease_id = disease.get("disease_id")
            if not disease_id:
                continue
            disease_rows.append(
                {
                    "disease_id": disease_id,
                    "name": disease.get("disease_name_zh"),
                    "name_en": disease.get("disease_name_en"),
                    "diet_pattern": json_text(disease.get("diet_pattern", {})),
                    "risk_notes": json_text(disease.get("risk_notes", [])),
                }
            )

            for relation in disease.get("disease_nutrient_relations", []):
                nutrition_id = relation.get("nutrient_id")
                if not nutrition_id:
                    continue
                target_rule = relation.get("target_rule", {})
                food_level_rule = relation.get("food_level_rule", {})
                rule_rows.append(
                    {
                        "disease_id": disease_id,
                        "nutrition_id": nutrition_id,
                        "nutrient_name": relation.get("nutrient_name_zh"),
                        "nutrient_name_en": relation.get("nutrient_name_en"),
                        "relation": relation.get("relation"),
                        "direction": target_rule.get("direction"),
                        "target_note": target_rule.get("note"),
                        "food_level_condition": food_level_rule.get("condition"),
                        "food_level": food_level_rule.get("level"),
                        "food_level_note": food_level_rule.get("note"),
                        "criteria_json": json_text(target_rule.get("criteria", [])),
                        "food_level_rule_json": json_text(food_level_rule),
                        "example_foods_json": json_text(relation.get("example_foods", [])),
                        "reason": relation.get("reason"),
                        "sources_json": json_text(relation.get("sources", [])),
                    }
                )

        disease_query = """
        UNWIND $rows AS row
        MERGE (d:Disease {disease_id: row.disease_id})
        SET d.name = row.name,
            d.name_en = row.name_en,
            d.diet_pattern = row.diet_pattern,
            d.risk_notes = row.risk_notes,
            d.source = $source,
            d.updated_by_version = $version
        """
        rule_query = """
        UNWIND $rows AS row
        MATCH (d:Disease {disease_id: row.disease_id})
        MERGE (n:Nutrition {nutrition_id: row.nutrition_id})
        SET n.name = coalesce(n.name, row.nutrient_name),
            n.name_zh = coalesce(n.name_zh, row.nutrient_name),
            n.name_en = coalesce(n.name_en, row.nutrient_name_en),
            n.updated_by_version = $version
        MERGE (d)-[r:HAS_DIET_RULE]->(n)
        SET r.relation = row.relation,
            r.rule_type = row.relation,
            r.direction = row.direction,
            r.target_note = row.target_note,
            r.note = row.target_note,
            r.food_level_condition = row.food_level_condition,
            r.food_level = row.food_level,
            r.food_level_note = row.food_level_note,
            r.criteria_json = row.criteria_json,
            r.food_level_rule_json = row.food_level_rule_json,
            r.example_foods_json = row.example_foods_json,
            r.reason = row.reason,
            r.sources_json = row.sources_json,
            r.source = $source,
            r.updated_by_version = $version
        """
        self._run_batches(disease_query, disease_rows, source=str(DISEASE_RULES_PATH), version=VERSION)
        self._run_batches(rule_query, rule_rows, source=str(DISEASE_RULES_PATH), version=VERSION)

    def import_all(self, *, clear: bool = False, limit_recipes: Optional[int] = None) -> None:
        if clear:
            self.clear_graph()
        self.create_schema()
        sources = self.load_sources()
        mapping_rows = sources["mapping"][:limit_recipes] if limit_recipes else sources["mapping"]

        self.import_nutrition_components()
        self.import_food_items_and_nutrition(sources["food_rows"])
        self.import_recipes_and_mappings(mapping_rows)
        self.import_disease_rules(sources["disease_rules"])

    def counts(self) -> Dict[str, List[Dict[str, Any]]]:
        with self.driver.session() as session:
            nodes = session.run(
                """
                MATCH (n)
                RETURN labels(n) AS labels, count(*) AS count
                ORDER BY count DESC
                """
            ).data()
            relationships = session.run(
                """
                MATCH ()-[r]->()
                RETURN type(r) AS type, count(*) AS count
                ORDER BY count DESC
                """
            ).data()
        return {"nodes": nodes, "relationships": relationships}

    def _run_batches(self, query: str, rows: List[Dict[str, Any]], **params: Any) -> None:
        with self.driver.session() as session:
            for chunk in batches(rows):
                session.run(query, rows=chunk, **params).consume()

    @staticmethod
    def _nutrition_display_name(nutrient: Dict[str, Any], name_counts: Dict[str, int]) -> str:
        name = str(nutrient.get("name_zh") or "").strip()
        if name_counts.get(name, 0) <= 1:
            return name
        source_column = str(nutrient.get("source_column") or "").strip()
        return source_column or f"{name} [{nutrient.get('nutrition_id')}]"


def main() -> None:
    parser = argparse.ArgumentParser(description="Import dietary knowledge agent data into Neo4j.")
    parser.add_argument("--clear", action="store_true", help="Delete all existing Neo4j data before import.")
    parser.add_argument("--limit-recipes", type=int, default=None, help="Import only the first N recipes for testing.")
    args = parser.parse_args()

    importer = KnowledgeAgentImporter(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)
    try:
        importer.import_all(clear=args.clear, limit_recipes=args.limit_recipes)
        print(json.dumps(importer.counts(), ensure_ascii=False, indent=2))
    finally:
        importer.close()


if __name__ == "__main__":
    main()
