from __future__ import annotations

import argparse
import json
import os
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set

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
RECIPE_DATA_DIR = DATA_DIR / "recipe_and_nutrition"
DISEASE_DATA_DIR = DATA_DIR / "disease_and_biomarker"

RECIPE_MAPPING_PATH = RECIPE_DATA_DIR / "recipes_json"
# Backward-compatible name used by the recipe-only entry point.
FOOD_MAPPING_PATH = RECIPE_MAPPING_PATH
NUTRITION_DATA_PATH = RECIPE_DATA_DIR / "nutrition_data_categorized.json"
NUTRITION_COMPONENTS_PATH = RECIPE_DATA_DIR / "nutrition_components.json"
DISEASE_RULES_PATH = DISEASE_DATA_DIR / "chronic_disease_rules_v2.json"

VERSION = "knowledge_agent_importer_v2"
FOOD_ID_FIELD = "整合編號"
FOOD_NAME_FIELD = "樣品名稱"
FOOD_CATEGORY_FIELD = "食品分類"
FOOD_ALIAS_FIELD = "俗名"


def load_env_files() -> None:
    env_paths = [
        BASE_DIR / ".env",
        Path(__file__).resolve().parent / ".env",
        BASE_DIR.parent / ".env",
        BASE_DIR.parents[1] / ".env",
    ]
    for env_path in env_paths:
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
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_recipe_records(path: Path) -> List[Dict[str, Any]]:
    """Load recipe records from one JSON file or every JSON file in a directory."""
    source = Path(path)
    paths = sorted(source.glob("*.json")) if source.is_dir() else [source]
    if not paths:
        raise FileNotFoundError(f"No JSON recipe files found in: {source}")

    records: List[Dict[str, Any]] = []
    for recipe_path in paths:
        data = load_json(recipe_path)
        if not isinstance(data, list):
            raise ValueError(f"Recipe mapping must be a JSON list: {recipe_path}")
        records.extend(row for row in data if isinstance(row, dict))
    return records


def safe_float(value: Any) -> Optional[float]:
    if value in {None, ""}:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def clean_text(value: Any) -> str:
    return str(value or "").strip()


def clean_food_id(value: Any) -> str:
    """Normalize mapping IDs that contain accidental line breaks or spaces."""
    text = clean_text(value)
    return text.splitlines()[0].strip() if text else ""


def json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def batches(items: List[Dict[str, Any]], size: int = 500) -> Iterable[List[Dict[str, Any]]]:
    for index in range(0, len(items), size):
        yield items[index : index + size]


class KnowledgeAgentImporter:
    """Build the current Dish/FoodItem/Nutrition/Disease graph from JSON sources."""

    def __init__(
        self,
        uri: str,
        user: str,
        password: str,
        *,
        nutrition_data_path: Path = NUTRITION_DATA_PATH,
        nutrition_components_path: Path = NUTRITION_COMPONENTS_PATH,
        disease_rules_path: Path = DISEASE_RULES_PATH,
    ) -> None:
        self.driver = GraphDatabase.driver(uri, auth=(user, password))
        self.nutrition_data_path = Path(nutrition_data_path)
        self.nutrition_components_path = Path(nutrition_components_path)
        self.disease_rules_path = Path(disease_rules_path)
        self.nutrients: List[Dict[str, Any]] = []
        self.nutrient_by_id: Dict[str, Dict[str, Any]] = {}
        self.nutrient_by_column: Dict[str, Dict[str, Any]] = {}
        self.food_by_id: Dict[str, Dict[str, Any]] = {}
        self.existing_food_ids_by_original: Dict[str, Set[str]] = defaultdict(set)

    def close(self) -> None:
        self.driver.close()

    def create_schema(self) -> None:
        """Create only constraints and indexes described by the current schema."""
        queries = [
            "CREATE CONSTRAINT dish_recipe_id_unique IF NOT EXISTS FOR (n:Dish) REQUIRE n.recipe_id IS UNIQUE",
            "CREATE CONSTRAINT ingredient_name_unique IF NOT EXISTS FOR (n:Ingredient) REQUIRE n.name IS UNIQUE",
            "CREATE CONSTRAINT ingredient_matched_food_id_required IF NOT EXISTS FOR (n:Ingredient) REQUIRE n.matched_food_id IS NOT NULL",
            "CREATE CONSTRAINT disease_name_unique IF NOT EXISTS FOR (n:Disease) REQUIRE n.name IS UNIQUE",
            "CREATE CONSTRAINT disease_id_unique IF NOT EXISTS FOR (n:Disease) REQUIRE n.disease_id IS UNIQUE",
            "CREATE CONSTRAINT nutrition_name_unique IF NOT EXISTS FOR (n:Nutrition) REQUIRE n.name IS UNIQUE",
            "CREATE CONSTRAINT nutrition_id_unique IF NOT EXISTS FOR (n:Nutrition) REQUIRE n.nutrition_id IS UNIQUE",
            "CREATE CONSTRAINT fooditem_food_id_unique IF NOT EXISTS FOR (n:FoodItem) REQUIRE n.food_id IS UNIQUE",
            "CREATE INDEX dish_name_index IF NOT EXISTS FOR (n:Dish) ON (n.name)",
            "CREATE INDEX fooditem_name_index IF NOT EXISTS FOR (n:FoodItem) ON (n.name)",
            "CREATE INDEX ingredient_matched_food_name_index IF NOT EXISTS FOR (n:Ingredient) ON (n.matched_food_name)",
            "CREATE INDEX nutrition_category_index IF NOT EXISTS FOR (n:Nutrition) ON (n.category)",
            "CREATE INDEX nutrition_is_core_index IF NOT EXISTS FOR (n:Nutrition) ON (n.is_core)",
        ]
        with self.driver.session() as session:
            for query in queries:
                session.run(query).consume()

    def clear_graph(self) -> None:
        with self.driver.session() as session:
            session.run("MATCH (n) DETACH DELETE n").consume()

    def load_nutrition_sources(self) -> Dict[str, int]:
        """Load all Nutrition definitions and every unique FoodItem row."""
        components = load_json(self.nutrition_components_path)
        self.nutrients = [
            nutrient
            for nutrient in components.get("nutrients", [])
            if clean_text(nutrient.get("nutrition_id")) and clean_text(nutrient.get("source_column"))
        ]
        self.nutrient_by_id = {
            clean_text(nutrient["nutrition_id"]): nutrient for nutrient in self.nutrients
        }
        self.nutrient_by_column = {
            clean_text(nutrient["source_column"]): nutrient for nutrient in self.nutrients
        }

        categorized = load_json(self.nutrition_data_path)
        raw_food_rows = [
            row
            for category_rows in categorized.values()
            if isinstance(category_rows, list)
            for row in category_rows
            if isinstance(row, dict)
        ]

        # The source contains repeated rows for some IDs. Keep one deterministic row.
        self.food_by_id = {}
        for row in raw_food_rows:
            food_id = clean_food_id(row.get(FOOD_ID_FIELD))
            if food_id and food_id not in self.food_by_id:
                self.food_by_id[food_id] = row

        return {
            "nutrition_definitions": len(self.nutrients),
            "food_rows_in_source": len(raw_food_rows),
            "food_items_unique": len(self.food_by_id),
        }

    def load_food_index_from_database(self) -> None:
        with self.driver.session() as session:
            rows = session.run("MATCH (f:FoodItem) RETURN f.food_id AS food_id, f.name AS name").data()
        self.food_by_id = {
            clean_text(row["food_id"]): {FOOD_NAME_FIELD: row.get("name")}
            for row in rows
            if clean_text(row.get("food_id"))
        }
        self.load_existing_ingredient_index_from_database()

    def load_existing_ingredient_index_from_database(self) -> None:
        with self.driver.session() as session:
            ingredient_rows = session.run(
                """
                MATCH (i:Ingredient)
                RETURN properties(i) AS properties
                """
            ).data()
        self.existing_food_ids_by_original = defaultdict(set)
        for row in ingredient_rows:
            properties = row.get("properties") or {}
            original_name = clean_text(properties.get("original_name") or properties.get("name"))
            food_id = clean_food_id(properties.get("matched_food_id"))
            if original_name and food_id:
                self.existing_food_ids_by_original[original_name].add(food_id)

    def import_nutrition_components(self) -> int:
        name_counts: Dict[str, int] = defaultdict(int)
        for nutrient in self.nutrients:
            name_counts[clean_text(nutrient.get("name_zh"))] += 1

        rows = []
        for nutrient in self.nutrients:
            nutrition_id = clean_text(nutrient.get("nutrition_id"))
            name_zh = clean_text(nutrient.get("name_zh"))
            source_column = clean_text(nutrient.get("source_column"))
            display_name = name_zh if name_counts[name_zh] == 1 else source_column
            rows.append(
                {
                    "nutrition_id": nutrition_id,
                    "name": display_name,
                    "name_zh": name_zh,
                    "name_en": clean_text(nutrient.get("name_en")),
                    "unit": clean_text(nutrient.get("unit")),
                    "category": clean_text(nutrient.get("category")),
                    "source_column": source_column,
                }
            )

        query = """
        UNWIND $rows AS row
        MERGE (n:Nutrition {nutrition_id: row.nutrition_id})
        SET n.name = row.name,
            n.name_zh = row.name_zh,
            n.name_en = row.name_en,
            n.unit = row.unit,
            n.category = row.category,
            n.source_column = row.source_column
        """
        self._run_batches(query, rows)
        return len(rows)

    def import_food_items_and_nutrition(self) -> Dict[str, int]:
        food_rows = []
        nutrition_rows = []
        for food_id, row in self.food_by_id.items():
            food_name = clean_text(row.get(FOOD_NAME_FIELD))
            if not food_name:
                continue
            alias = row.get(FOOD_ALIAS_FIELD)
            food_rows.append(
                {
                    "food_id": food_id,
                    "name": food_name,
                    "category": row.get(FOOD_CATEGORY_FIELD),
                    "description": row.get("內容物描述"),
                    "alias": alias,
                    "aliases": alias,
                }
            )
            for source_column, nutrient in self.nutrient_by_column.items():
                amount = safe_float(row.get(source_column))
                if amount is None:
                    continue
                nutrition_rows.append(
                    {
                        "food_id": food_id,
                        "nutrition_id": clean_text(nutrient["nutrition_id"]),
                        "amount_per_100g": amount,
                        "value_per_100g": amount,
                        "unit": clean_text(nutrient.get("unit")),
                        "basis": "per_100g",
                        "source_column": source_column,
                    }
                )

        food_query = """
        UNWIND $rows AS row
        MERGE (f:FoodItem {food_id: row.food_id})
        SET f.name = row.name,
            f.category = row.category,
            f.description = row.description,
            f.alias = row.alias,
            f.aliases = row.aliases
        """
        nutrition_query = """
        UNWIND $rows AS row
        MATCH (f:FoodItem {food_id: row.food_id})
        MATCH (n:Nutrition {nutrition_id: row.nutrition_id})
        MERGE (f)-[r:HAS_NUTRITION]->(n)
        SET r.amount_per_100g = row.amount_per_100g,
            r.value_per_100g = row.value_per_100g,
            r.unit = row.unit,
            r.basis = row.basis,
            r.source_column = row.source_column
        """
        self._run_batches(food_query, food_rows)
        self._run_batches(nutrition_query, nutrition_rows)
        return {"food_items": len(food_rows), "has_nutrition": len(nutrition_rows)}

    def import_recipes_from_json(
        self,
        mapping_path: Path,
        *,
        strict_mapping: bool = False,
        limit_recipes: Optional[int] = None,
    ) -> Dict[str, Any]:
        records = load_recipe_records(Path(mapping_path))

        if not self.food_by_id:
            self.load_food_index_from_database()
        else:
            self.load_existing_ingredient_index_from_database()

        recipe_rows, ingredient_rows, report = self._prepare_recipe_rows(
            records[:limit_recipes] if limit_recipes else records,
            strict_mapping=strict_mapping,
        )
        self._remove_old_recipe_relationships([row["recipe_id"] for row in recipe_rows])
        self._write_recipe_rows(recipe_rows)
        return {
            "mapping_path": str(mapping_path),
            "recipes_written": len(recipe_rows),
            "ingredients_written": len(ingredient_rows),
            **report,
        }

    def _prepare_recipe_rows(
        self,
        records: List[Dict[str, Any]],
        *,
        strict_mapping: bool,
    ) -> tuple[List[Dict[str, Any]], List[Dict[str, Any]], Dict[str, Any]]:
        source_food_ids: Dict[str, Set[str]] = defaultdict(set)
        for original, food_ids in self.existing_food_ids_by_original.items():
            source_food_ids[original].update(food_ids)
        missing_counter: Dict[str, int] = defaultdict(int)
        duplicate_recipe_ids = 0

        for recipe in records:
            for ingredient in recipe.get("resolved_ingredients", []):
                original = clean_text(ingredient.get("original"))
                food_id = clean_food_id(ingredient.get(FOOD_ID_FIELD))
                if original and food_id in self.food_by_id:
                    source_food_ids[original].add(food_id)
                elif original:
                    missing_counter[food_id or "<empty>"] += 1

        if strict_mapping and missing_counter:
            missing = ", ".join(f"{key}: {count}" for key, count in sorted(missing_counter.items()))
            raise ValueError(f"Recipe mapping contains FoodItem IDs not available in the database: {missing}")

        recipe_by_id: Dict[str, Dict[str, Any]] = {}
        for recipe in records:
            recipe_id = clean_text(recipe.get("recipe_id"))
            if not recipe_id:
                continue
            if recipe_id in recipe_by_id:
                duplicate_recipe_ids += 1
            recipe_by_id[recipe_id] = recipe

        recipe_rows: List[Dict[str, Any]] = []
        ingredient_by_key: Dict[str, Dict[str, Any]] = {}
        skipped_ingredients = 0
        duplicate_ingredients_collapsed = 0

        for recipe in recipe_by_id.values():
            recipe_id = clean_text(recipe.get("recipe_id"))
            recipe_name = clean_text(recipe.get("recipe_name"))
            if not recipe_name:
                continue

            grouped: Dict[str, Dict[str, Any]] = {}
            for order, ingredient in enumerate(recipe.get("resolved_ingredients", []), start=1):
                original = clean_text(ingredient.get("original"))
                food_id = clean_food_id(ingredient.get(FOOD_ID_FIELD))
                if not original or food_id not in self.food_by_id:
                    skipped_ingredients += 1
                    continue

                ingredient_key = self._ingredient_key(original, food_id, source_food_ids)
                prepared = {
                    "ingredient_key": ingredient_key,
                    "original_name": original,
                    "matched_food_id": food_id,
                    "matched_food_name": clean_text(ingredient.get("matched"))
                    or clean_text(self.food_by_id[food_id].get(FOOD_NAME_FIELD)),
                    "amount_raw": ingredient.get("amount_raw"),
                    "amount": safe_float(ingredient.get("amount_value")),
                    "amount_value": safe_float(ingredient.get("amount_value")),
                    "amount_unit": ingredient.get("amount_unit"),
                    "unit": ingredient.get("amount_unit"),
                    "amount_note": ingredient.get("amount_note"),
                    "amount_per_serving": safe_float(ingredient.get("amount_per_serving")),
                    "order": order,
                }
                if ingredient_key in grouped:
                    duplicate_ingredients_collapsed += 1
                    self._merge_ingredient_amounts(grouped[ingredient_key], prepared)
                else:
                    grouped[ingredient_key] = prepared
                    ingredient_by_key[ingredient_key] = prepared

            recipe_rows.append(
                {
                    "recipe_id": recipe_id,
                    "name": recipe_name,
                    "servings": recipe.get("servings"),
                    "ingredient_count": len(grouped),
                    "ingredients": list(grouped.values()),
                }
            )

        return (
            recipe_rows,
            list(ingredient_by_key.values()),
            {
                "input_recipes": len(records),
                "duplicate_recipe_ids_collapsed": duplicate_recipe_ids,
                "skipped_unmapped_ingredients": skipped_ingredients,
                "unmapped_food_ids": dict(sorted(missing_counter.items())),
                "conflicting_original_names_split": sum(1 for ids in source_food_ids.values() if len(ids) > 1),
                "duplicate_ingredients_collapsed": duplicate_ingredients_collapsed,
            },
        )

    @staticmethod
    def _ingredient_key(original: str, food_id: str, source_food_ids: Dict[str, Set[str]]) -> str:
        if len(source_food_ids.get(original, set())) <= 1:
            return original
        return f"{original} [{food_id}]"

    @staticmethod
    def _merge_ingredient_amounts(target: Dict[str, Any], source: Dict[str, Any]) -> None:
        for field in ("amount", "amount_value", "amount_per_serving"):
            values = [target.get(field), source.get(field)]
            numbers = [value for value in values if value is not None]
            target[field] = sum(numbers) if numbers else None

        raw_values = [clean_text(target.get("amount_raw")), clean_text(source.get("amount_raw"))]
        target["amount_raw"] = "; ".join(dict.fromkeys(value for value in raw_values if value)) or None
        note_values = [clean_text(target.get("amount_note")), clean_text(source.get("amount_note"))]
        target["amount_note"] = "; ".join(dict.fromkeys(value for value in note_values if value)) or None

    def _remove_old_recipe_relationships(self, recipe_ids: List[str]) -> None:
        query = """
        UNWIND $recipe_ids AS recipe_id
        MATCH (d:Dish {recipe_id: recipe_id})-[r:CONTAINS]->()
        DELETE r
        """
        for start in range(0, len(recipe_ids), 500):
            self._run_query(query, recipe_ids=recipe_ids[start : start + 500])

    def _write_recipe_rows(self, recipe_rows: List[Dict[str, Any]]) -> None:
        recipe_query = """
        UNWIND $rows AS row
        MERGE (d:Dish {recipe_id: row.recipe_id})
        SET d.name = row.name,
            d.servings = row.servings,
            d.ingredient_count = row.ingredient_count
        WITH d, row
        UNWIND row.ingredients AS ing
        MERGE (i:Ingredient {name: ing.ingredient_key})
        SET i.matched_food_id = ing.matched_food_id,
            i.matched_food_name = ing.matched_food_name,
            i.original_name = ing.original_name
        MERGE (d)-[c:CONTAINS]->(i)
        SET c.matched_food_id = ing.matched_food_id,
            c.matched_food_name = ing.matched_food_name,
            c.original_name = ing.original_name,
            c.amount_raw = ing.amount_raw,
            c.amount = ing.amount,
            c.amount_value = ing.amount_value,
            c.unit = ing.unit,
            c.amount_unit = ing.amount_unit,
            c.amount_note = ing.amount_note,
            c.amount_per_serving = ing.amount_per_serving,
            c.order = ing.order
        """
        mapping_query = """
        UNWIND $rows AS row
        MATCH (i:Ingredient {name: row.ingredient_key})
        MATCH (f:FoodItem {food_id: row.matched_food_id})
        OPTIONAL MATCH (i)-[old:MAPS_TO]->()
        DELETE old
        WITH DISTINCT i, f
        MERGE (i)-[:MAPS_TO]->(f)
        """

        for chunk in batches(recipe_rows):
            self._run_query(recipe_query, rows=chunk)
        mappings = self._unique_mappings(recipe_rows)
        for chunk in batches(mappings):
            self._run_query(mapping_query, rows=chunk)

    @staticmethod
    def _unique_mappings(recipe_rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        mappings: Dict[str, Dict[str, Any]] = {}
        for recipe in recipe_rows:
            for ingredient in recipe["ingredients"]:
                mappings[ingredient["ingredient_key"]] = {
                    "ingredient_key": ingredient["ingredient_key"],
                    "matched_food_id": ingredient["matched_food_id"],
                }
        return list(mappings.values())

    def import_disease_rules(self) -> Dict[str, int]:
        data = load_json(self.disease_rules_path)
        disease_rows = []
        rule_rows = []
        skipped_relations = 0

        for disease in data.get("diseases", []):
            disease_id = clean_text(disease.get("disease_id"))
            disease_name = clean_text(disease.get("disease_name_zh"))
            if not disease_id or not disease_name:
                continue
            disease_rows.append(
                {
                    "disease_id": disease_id,
                    "name": disease_name,
                    "name_en": clean_text(disease.get("disease_name_en")),
                    "diet_pattern": json_text(disease.get("diet_pattern", {})),
                    "risk_notes": json_text(disease.get("risk_notes", [])),
                }
            )

            for relation in disease.get("disease_nutrient_relations", []):
                targets = self._disease_relation_targets(relation)
                if not targets:
                    skipped_relations += 1
                    continue
                target_rule = relation.get("target_rule") or {}
                food_level_rule = relation.get("food_level_rule") or {}
                for nutrition_id in targets:
                    rule_rows.append(
                        {
                            "disease_id": disease_id,
                            "nutrition_id": nutrition_id,
                            "relation": clean_text(relation.get("relation")),
                            "rule_type": clean_text(relation.get("relation")),
                            "direction": clean_text(target_rule.get("direction")),
                            "target_note": target_rule.get("note"),
                            "food_level_condition": food_level_rule.get("condition"),
                            "food_level": food_level_rule.get("level"),
                            "food_level_note": food_level_rule.get("note"),
                            "criteria_json": json_text(target_rule.get("criteria", [])),
                            "food_level_rule_json": json_text(food_level_rule),
                            "example_foods_json": json_text(relation.get("example_foods", [])),
                            "reason": relation.get("reason"),
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
        MATCH (n:Nutrition {nutrition_id: row.nutrition_id})
        MERGE (d)-[r:HAS_DIET_RULE]->(n)
        SET r.rule_type = row.rule_type,
            r.relation = row.relation,
            r.direction = row.direction,
            r.target_note = row.target_note,
            r.food_level_condition = row.food_level_condition,
            r.food_level = row.food_level,
            r.food_level_note = row.food_level_note,
            r.criteria_json = row.criteria_json,
            r.food_level_rule_json = row.food_level_rule_json,
            r.example_foods_json = row.example_foods_json,
            r.reason = row.reason
        """
        unique_rule_rows = {
            (row["disease_id"], row["nutrition_id"]): row for row in rule_rows
        }
        self._run_batches(disease_query, disease_rows, source=str(self.disease_rules_path), version=VERSION)
        self._run_batches(rule_query, list(unique_rule_rows.values()))
        return {
            "diseases": len(disease_rows),
            "disease_rule_relations": len(unique_rule_rows),
            "duplicate_disease_rule_relations_collapsed": len(rule_rows) - len(unique_rule_rows),
            "skipped_unmapped_disease_relations": skipped_relations,
        }

    def _disease_relation_targets(self, relation: Dict[str, Any]) -> List[str]:
        direct_id = clean_text(relation.get("nutrient_id"))
        if direct_id in self.nutrient_by_id:
            return [direct_id]

        mapped = []
        for item in relation.get("mapped_nutrients", []) or []:
            nutrition_id = clean_text(item.get("nutrition_id"))
            if nutrition_id in self.nutrient_by_id and nutrition_id not in mapped:
                mapped.append(nutrition_id)
        return mapped

    def import_all(
        self,
        *,
        clear: bool = False,
        mapping_path: Path = FOOD_MAPPING_PATH,
        strict_mapping: bool = False,
        limit_recipes: Optional[int] = None,
    ) -> Dict[str, Any]:
        if clear:
            self.clear_graph()
        self.create_schema()
        nutrition_source_report = self.load_nutrition_sources()
        nutrition_count = self.import_nutrition_components()
        food_report = self.import_food_items_and_nutrition()
        recipe_report = self.import_recipes_from_json(
            mapping_path,
            strict_mapping=strict_mapping,
            limit_recipes=limit_recipes,
        )
        disease_report = self.import_disease_rules()
        return {
            "nutrition_source": nutrition_source_report,
            "nutrition_nodes_written": nutrition_count,
            "food_import": food_report,
            "recipe_import": recipe_report,
            "disease_import": disease_report,
            "counts": self.counts(),
            "mapping_violations": self.mapping_violations(),
        }

    def counts(self) -> Dict[str, List[Dict[str, Any]]]:
        with self.driver.session() as session:
            nodes = session.run(
                """
                MATCH (n)
                UNWIND labels(n) AS label
                RETURN label, count(*) AS count
                ORDER BY label
                """
            ).data()
            relationships = session.run(
                """
                MATCH (a)-[r]->(b)
                RETURN labels(a) AS from_labels, type(r) AS type,
                       labels(b) AS to_labels, count(*) AS count
                ORDER BY type
                """
            ).data()
        return {"nodes": nodes, "relationships": relationships}

    def mapping_violations(self) -> List[Dict[str, Any]]:
        query = """
        MATCH (i:Ingredient)
        OPTIONAL MATCH (i)-[m:MAPS_TO]->(f:FoodItem)
        WITH i, count(m) AS map_count, collect(f.food_id) AS mapped_food_ids
        WHERE map_count <> 1 OR mapped_food_ids[0] <> i.matched_food_id
        RETURN i.name AS ingredient_name,
               i.matched_food_id AS expected_food_id,
               map_count,
               mapped_food_ids
        ORDER BY ingredient_name
        """
        with self.driver.session() as session:
            return session.run(query).data()

    def _run_batches(self, query: str, rows: List[Dict[str, Any]], **params: Any) -> None:
        if not rows:
            return
        with self.driver.session() as session:
            for chunk in batches(rows):
                session.run(query, rows=chunk, **params).consume()

    def _run_query(self, query: str, **params: Any) -> None:
        with self.driver.session() as session:
            session.run(query, **params).consume()


def main() -> None:
    parser = argparse.ArgumentParser(description="Import the dietary knowledge graph into Neo4j.")
    parser.add_argument("--clear", action="store_true", help="Delete all graph data before importing.")
    parser.add_argument("--mapping-path", type=Path, default=FOOD_MAPPING_PATH)
    parser.add_argument("--strict-mapping", action="store_true")
    parser.add_argument("--limit-recipes", type=int, default=None)
    parser.add_argument("--nutrition-data-path", type=Path, default=NUTRITION_DATA_PATH)
    parser.add_argument("--nutrition-components-path", type=Path, default=NUTRITION_COMPONENTS_PATH)
    parser.add_argument("--disease-rules-path", type=Path, default=DISEASE_RULES_PATH)
    args = parser.parse_args()

    importer = KnowledgeAgentImporter(
        NEO4J_URI,
        NEO4J_USER,
        NEO4J_PASSWORD,
        nutrition_data_path=args.nutrition_data_path,
        nutrition_components_path=args.nutrition_components_path,
        disease_rules_path=args.disease_rules_path,
    )
    try:
        result = importer.import_all(
            clear=args.clear,
            mapping_path=args.mapping_path,
            strict_mapping=args.strict_mapping,
            limit_recipes=args.limit_recipes,
        )
        print(json.dumps(result, ensure_ascii=False, indent=2))
    finally:
        importer.close()


if __name__ == "__main__":
    main()
