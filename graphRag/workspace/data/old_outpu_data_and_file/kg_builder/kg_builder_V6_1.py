"""
kg_builder_V6_1.py

Version History
---------------
V6.1 (2026-04-19)

[Added]
- 將 disease rules 改由 JSON 載入
- 將 biomarker-nutrient links 改由 JSON 載入
- 固定使用 Nutrient -> Biomarker 的方向
- 新增示範查詢：Dish -> Ingredient -> Nutrient -> Biomarker
- 新增 JSON 檔案不存在時的明確錯誤訊息

[Changed]
- Disease / Biomarker / Rule seed 不再硬編碼在 Python 內
- 改善程式可讀性，讓規則資料與建圖程式分離
- Disease 與 Biomarker 的匯入流程改為讀 data/*.json

[Removed]
- 移除程式內 DISEASE_RULES 常數
- 移除程式內 BIOMARKER_NUTRIENT_LINKS 常數

[Fixed]
- 修正 Biomarker 與 Nutrient 關係方向，改為：
  Nutrient -[:AFFECTS_BIOMARKER]-> Biomarker

[Notes]
- 本版本的主知識鏈為：
  Dish -> Ingredient -> FoodItem -> Nutrient -> Biomarker
- Disease 作為規則層存在，不建議在主展示 query 中同時拉出
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from neo4j import GraphDatabase


VERSION = "V6.1"

NEO4J_URI = os.getenv("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")

RECIPE_SOURCE_NAME = "recipes.json"
RECIPE_SOURCE_TYPE = "recipe_file"

MAPPING_SOURCE_NAME = "ingredient_mapping.json"
MAPPING_SOURCE_TYPE = "mapping_file"

NUTRITION_SOURCE_NAME = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json"
NUTRITION_SOURCE_TYPE = "nutrition_file"

DISEASE_RULE_SOURCE_NAME = "disease_rules.json"
DISEASE_RULE_SOURCE_TYPE = "manual_rule_seed"

BIOMARKER_LINK_SOURCE_NAME = "biomarker_nutrient_links.json"
BIOMARKER_LINK_SOURCE_TYPE = "manual_rule_seed"

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"

RECIPES_PATH = DATA_DIR / "recipes.json"
INGREDIENT_MAPPING_PATH = DATA_DIR / "ingredient_mapping.json"
NUTRITION_DATA_PATH = DATA_DIR / "nutrition_data.json"
DISEASE_RULES_PATH = DATA_DIR / "disease_rules.json"
BIOMARKER_LINKS_PATH = DATA_DIR / "biomarker_nutrient_links.json"

TEST_RECIPE_IDS = {
    "r481005",
    "r481002",
}

NUTRIENT_FIELD_MAP: Dict[str, Tuple[str, str]] = {
    "熱量(kcal)": ("熱量", "kcal/100g"),
    "修正熱量(kcal)": ("修正熱量", "kcal/100g"),
    "粗蛋白(g)": ("蛋白質", "g/100g"),
    "粗脂肪(g)": ("脂肪", "g/100g"),
    "飽和脂肪(g)": ("飽和脂肪", "g/100g"),
    "總碳水化合物(g)": ("碳水化合物", "g/100g"),
    "膳食纖維(g)": ("膳食纖維", "g/100g"),
    "糖質總量(g)": ("糖", "g/100g"),
    "鈉(mg)": ("鈉", "mg/100g"),
    "鉀(mg)": ("鉀", "mg/100g"),
    "鈣(mg)": ("鈣", "mg/100g"),
    "鎂(mg)": ("鎂", "mg/100g"),
    "鐵(mg)": ("鐵", "mg/100g"),
    "鋅(mg)": ("鋅", "mg/100g"),
    "磷(mg)": ("磷", "mg/100g"),
    "膽固醇(mg)": ("膽固醇", "mg/100g"),
    "維生素C(mg)": ("維生素C", "mg/100g"),
    "維生素B1(mg)": ("維生素B1", "mg/100g"),
    "維生素B2(mg)": ("維生素B2", "mg/100g"),
    "維生素B6(mg)": ("維生素B6", "mg/100g"),
    "葉酸(ug)": ("葉酸", "ug/100g"),
}


@dataclass
class MappingResult:
    ingredient_name: str
    fooditem_name: str
    confidence: float
    mapping_source: str
    matched: bool


@dataclass
class NutritionMatchResult:
    matched: bool
    row: Optional[Dict[str, Any]]
    matched_by: str
    matched_key: str


class KGBuilderV61:
    def __init__(self) -> None:
        print(f"[KG Builder] Version: {VERSION}")
        print("Connecting to Neo4j...")

        self.driver = GraphDatabase.driver(
            NEO4J_URI,
            auth=(NEO4J_USER, NEO4J_PASSWORD),
        )

        self.mapping_lookup: Dict[str, Dict[str, Any]] = {}
        self.nutrition_by_name: Dict[str, Dict[str, Any]] = {}
        self.nutrition_by_alias: Dict[str, Dict[str, Any]] = {}
        self.disease_rules: List[Dict[str, Any]] = []
        self.biomarker_links: List[Dict[str, Any]] = []

    def close(self) -> None:
        self.driver.close()

    @staticmethod
    def normalize_key(text: Optional[str]) -> str:
        if text is None:
            return ""
        return str(text).strip().lower()

    @staticmethod
    def safe_float(value: Any, default: Optional[float] = None) -> Optional[float]:
        try:
            if value is None or value == "":
                return default
            return float(value)
        except (TypeError, ValueError):
            return default

    @staticmethod
    def split_aliases(alias_text: Optional[str]) -> List[str]:
        if not alias_text:
            return []
        raw = str(alias_text)
        for sep in [",", "，", ";", "；", "/", "、"]:
            raw = raw.replace(sep, "|")
        return [x.strip() for x in raw.split("|") if x.strip()]

    def create_schema(self) -> None:
        print("Creating schema...")

        queries = [
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (d:Dish) REQUIRE d.recipe_id IS UNIQUE
            """,
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (i:Ingredient) REQUIRE i.name IS UNIQUE
            """,
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (f:FoodItem) REQUIRE f.name IS UNIQUE
            """,
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (n:Nutrient) REQUIRE n.name IS UNIQUE
            """,
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (s:Source) REQUIRE s.name IS UNIQUE
            """,
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (d:Disease) REQUIRE d.name IS UNIQUE
            """,
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (b:Biomarker) REQUIRE b.name IS UNIQUE
            """,
            """
            CREATE INDEX IF NOT EXISTS
            FOR (d:Dish) ON (d.name)
            """,
            """
            CREATE INDEX IF NOT EXISTS
            FOR (d:Disease) ON (d.name)
            """,
        ]

        with self.driver.session() as session:
            for query in queries:
                session.run(query)

        print("Schema ready.")

    def load_json_file(self, path: Path, label: str) -> Any:
        if not path.exists():
            raise FileNotFoundError(f"{label} not found: {path}")
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)

    def load_test_recipes(self) -> List[Dict[str, Any]]:
        print(f"Loading recipes from: {RECIPES_PATH}")
        recipes = self.load_json_file(RECIPES_PATH, "recipes.json")

        if TEST_RECIPE_IDS:
            selected = [r for r in recipes if r.get(
                "recipe_id") in TEST_RECIPE_IDS]
        else:
            selected = recipes

        print(f"Loaded {len(selected)} recipe(s).")
        for recipe in selected:
            print(f"- {recipe.get('recipe_id')} | {recipe.get('name')}")

        return selected

    def load_ingredient_mapping(self) -> None:
        print(f"Loading ingredient mapping from: {INGREDIENT_MAPPING_PATH}")

        if not INGREDIENT_MAPPING_PATH.exists():
            print(
                "WARNING: ingredient_mapping.json not found. Will use fallback self-mapping.")
            self.mapping_lookup = {}
            return

        raw = self.load_json_file(
            INGREDIENT_MAPPING_PATH, "ingredient_mapping.json")
        lookup: Dict[str, Dict[str, Any]] = {}

        if isinstance(raw, dict) and all(not isinstance(v, (dict, list)) for v in raw.values()):
            for ingredient_key, fooditem_value in raw.items():
                lookup[self.normalize_key(ingredient_key)] = {
                    "ingredient_name": str(ingredient_key).strip(),
                    "fooditem_name": str(fooditem_value).strip(),
                    "confidence": 1.0,
                    "mapping_source": "ingredient_mapping.json:direct_dict",
                }

        elif isinstance(raw, dict):
            for ingredient_key, value in raw.items():
                norm_key = self.normalize_key(ingredient_key)
                if not isinstance(value, dict):
                    continue

                ingredient_name = (
                    value.get("ingredient_name")
                    or value.get("canonical_ingredient")
                    or value.get("name")
                    or ingredient_key
                )
                fooditem_name = (
                    value.get("fooditem_name")
                    or value.get("food_item")
                    or value.get("fooditem")
                    or value.get("mapped_to")
                    or ingredient_name
                )
                confidence = self.safe_float(value.get("confidence"), 1.0)

                lookup[norm_key] = {
                    "ingredient_name": str(ingredient_name).strip(),
                    "fooditem_name": str(fooditem_name).strip(),
                    "confidence": confidence,
                    "mapping_source": "ingredient_mapping.json:nested_dict",
                }

                aliases = value.get("aliases", [])
                if isinstance(aliases, list):
                    for alias in aliases:
                        lookup[self.normalize_key(alias)] = {
                            "ingredient_name": str(ingredient_name).strip(),
                            "fooditem_name": str(fooditem_name).strip(),
                            "confidence": confidence,
                            "mapping_source": "ingredient_mapping.json:alias_list",
                        }

        elif isinstance(raw, list):
            for item in raw:
                if not isinstance(item, dict):
                    continue

                source_name = (
                    item.get("source_name")
                    or item.get("ingredient_name")
                    or item.get("ingredient")
                    or item.get("raw_name")
                    or item.get("name")
                )
                if not source_name:
                    continue

                ingredient_name = (
                    item.get("canonical_ingredient")
                    or item.get("ingredient_name")
                    or item.get("ingredient")
                    or item.get("name")
                    or source_name
                )
                fooditem_name = (
                    item.get("fooditem_name")
                    or item.get("food_item")
                    or item.get("fooditem")
                    or item.get("mapped_to")
                    or ingredient_name
                )
                confidence = self.safe_float(item.get("confidence"), 1.0)

                lookup[self.normalize_key(source_name)] = {
                    "ingredient_name": str(ingredient_name).strip(),
                    "fooditem_name": str(fooditem_name).strip(),
                    "confidence": confidence,
                    "mapping_source": "ingredient_mapping.json:list",
                }

                aliases = item.get("aliases", [])
                if isinstance(aliases, list):
                    for alias in aliases:
                        lookup[self.normalize_key(alias)] = {
                            "ingredient_name": str(ingredient_name).strip(),
                            "fooditem_name": str(fooditem_name).strip(),
                            "confidence": confidence,
                            "mapping_source": "ingredient_mapping.json:list_alias",
                        }

        self.mapping_lookup = lookup
        print(f"Loaded {len(self.mapping_lookup)} mapping key(s).")

    def resolve_mapping(self, ingredient_name: str, raw_name: Optional[str] = None) -> MappingResult:
        candidates = [
            self.normalize_key(raw_name),
            self.normalize_key(ingredient_name),
        ]

        for key in candidates:
            if key and key in self.mapping_lookup:
                hit = self.mapping_lookup[key]
                return MappingResult(
                    ingredient_name=hit["ingredient_name"],
                    fooditem_name=hit["fooditem_name"],
                    confidence=float(hit.get("confidence", 1.0)),
                    mapping_source=hit.get(
                        "mapping_source", MAPPING_SOURCE_NAME),
                    matched=True,
                )

        canonical = ingredient_name.strip()
        return MappingResult(
            ingredient_name=canonical,
            fooditem_name=canonical,
            confidence=0.0,
            mapping_source="fallback_self_mapping",
            matched=False,
        )

    def load_nutrition_data(self) -> None:
        print(f"Loading nutrition data from: {NUTRITION_DATA_PATH}")

        if not NUTRITION_DATA_PATH.exists():
            print(
                "WARNING: nutrition_data.json not found. Nutrition import will be skipped.")
            self.nutrition_by_name = {}
            self.nutrition_by_alias = {}
            return

        rows = self.load_json_file(NUTRITION_DATA_PATH, "nutrition_data.json")

        by_name: Dict[str, Dict[str, Any]] = {}
        by_alias: Dict[str, Dict[str, Any]] = {}

        for row in rows:
            sample_name = row.get("樣品名稱")
            if sample_name:
                by_name[self.normalize_key(sample_name)] = row

            alias_text = row.get("俗名")
            for alias in self.split_aliases(alias_text):
                by_alias[self.normalize_key(alias)] = row

        self.nutrition_by_name = by_name
        self.nutrition_by_alias = by_alias

        print(
            f"Loaded nutrition rows: {len(rows)} | "
            f"name keys: {len(self.nutrition_by_name)} | "
            f"alias keys: {len(self.nutrition_by_alias)}"
        )

    def resolve_nutrition_row(self, fooditem_name: str) -> NutritionMatchResult:
        key = self.normalize_key(fooditem_name)

        if key in self.nutrition_by_name:
            return NutritionMatchResult(
                matched=True,
                row=self.nutrition_by_name[key],
                matched_by="樣品名稱",
                matched_key=fooditem_name,
            )

        if key in self.nutrition_by_alias:
            return NutritionMatchResult(
                matched=True,
                row=self.nutrition_by_alias[key],
                matched_by="俗名",
                matched_key=fooditem_name,
            )

        return NutritionMatchResult(
            matched=False,
            row=None,
            matched_by="",
            matched_key="",
        )

    def load_disease_rule_json(self) -> None:
        print(f"Loading disease rules from: {DISEASE_RULES_PATH}")
        self.disease_rules = self.load_json_file(
            DISEASE_RULES_PATH, "disease_rules.json")
        print(f"Loaded {len(self.disease_rules)} disease rule seed(s).")

    def load_biomarker_link_json(self) -> None:
        print(f"Loading biomarker links from: {BIOMARKER_LINKS_PATH}")
        self.biomarker_links = self.load_json_file(
            BIOMARKER_LINKS_PATH, "biomarker_nutrient_links.json")
        print(
            f"Loaded {len(self.biomarker_links)} biomarker-nutrient link(s).")

    def insert_recipe(self, recipe: Dict[str, Any]) -> None:
        recipe_id = recipe.get("recipe_id")
        dish_name = recipe.get("name")
        servings = recipe.get("servings")

        prepared_ingredients: List[Dict[str, Any]] = []

        for ing in recipe.get("ingredients", []):
            original_name = (ing.get("name") or "").strip()
            raw_name = ing.get("name_raw")
            mapping = self.resolve_mapping(original_name, raw_name)

            prepared_ingredients.append(
                {
                    "ingredient_name": mapping.ingredient_name,
                    "fooditem_name": mapping.fooditem_name,
                    "mapping_confidence": mapping.confidence,
                    "mapping_source": mapping.mapping_source,
                    "name_raw": raw_name,
                    "amount": ing.get("amount_value"),
                    "unit": ing.get("amount_unit"),
                    "amount_note": ing.get("amount_note"),
                }
            )

        query = """
        MERGE (d:Dish {recipe_id: $recipe_id})
        SET d.name = $dish_name,
            d.servings = $servings,
            d.builder_version = $version

        MERGE (recipe_source:Source {name: $recipe_source_name})
        SET recipe_source.type = $recipe_source_type
        MERGE (d)-[:EXTRACTED_FROM]->(recipe_source)

        MERGE (mapping_source_node:Source {name: $mapping_source_name})
        SET mapping_source_node.type = $mapping_source_type

        WITH d, mapping_source_node
        UNWIND $ingredients AS ing

        MERGE (i:Ingredient {name: ing.ingredient_name})
        ON CREATE SET i.created_by_version = $version

        MERGE (d)-[c:CONTAINS]->(i)
        SET c.amount = ing.amount,
            c.unit = ing.unit,
            c.amount_note = ing.amount_note,
            c.name_raw = ing.name_raw

        MERGE (f:FoodItem {name: ing.fooditem_name})
        ON CREATE SET f.created_by_version = $version

        MERGE (i)-[m:MAP_TO]->(f)
        SET m.confidence = ing.mapping_confidence,
            m.mapping_source = ing.mapping_source,
            m.mapped_by_version = $version

        MERGE (i)-[:MAPPED_FROM]->(mapping_source_node)
        """

        with self.driver.session() as session:
            session.run(
                query,
                recipe_id=recipe_id,
                dish_name=dish_name,
                servings=servings,
                ingredients=prepared_ingredients,
                recipe_source_name=RECIPE_SOURCE_NAME,
                recipe_source_type=RECIPE_SOURCE_TYPE,
                mapping_source_name=MAPPING_SOURCE_NAME,
                mapping_source_type=MAPPING_SOURCE_TYPE,
                version=VERSION,
            )

    def upsert_fooditem_nutrition(self, fooditem_name: str) -> None:
        matched = self.resolve_nutrition_row(fooditem_name)

        if not matched.matched or not matched.row:
            print(f"    [nutrition] NOT FOUND for FoodItem={fooditem_name}")
            return

        row = matched.row
        nutrition_values: List[Dict[str, Any]] = []

        for field_name, (nutrient_name, unit) in NUTRIENT_FIELD_MAP.items():
            value = self.safe_float(row.get(field_name), None)
            if value is None:
                continue

            nutrition_values.append(
                {
                    "nutrient_name": nutrient_name,
                    "amount": value,
                    "unit": unit,
                    "source_field": field_name,
                }
            )

        if not nutrition_values:
            print(
                f"    [nutrition] matched but no usable nutrient fields for FoodItem={fooditem_name}")
            return

        query = """
        MERGE (f:FoodItem {name: $fooditem_name})
        SET f.nutrition_sample_name = $sample_name,
            f.nutrition_category = $category,
            f.nutrition_match_by = $matched_by,
            f.nutrition_match_key = $matched_key

        MERGE (s:Source {name: $nutrition_source_name})
        SET s.type = $nutrition_source_type
        MERGE (f)-[:DERIVED_FROM]->(s)

        WITH f
        UNWIND $nutrition_values AS nv

        MERGE (n:Nutrient {name: nv.nutrient_name})
        ON CREATE SET n.created_by_version = $version

        MERGE (f)-[r:HAS_NUTRIENT]->(n)
        SET r.amount = nv.amount,
            r.unit = nv.unit,
            r.source_field = nv.source_field,
            r.data_version = $version
        """

        with self.driver.session() as session:
            session.run(
                query,
                fooditem_name=fooditem_name,
                sample_name=row.get("樣品名稱"),
                category=row.get("食品分類"),
                matched_by=matched.matched_by,
                matched_key=matched.matched_key,
                nutrition_source_name=NUTRITION_SOURCE_NAME,
                nutrition_source_type=NUTRITION_SOURCE_TYPE,
                nutrition_values=nutrition_values,
                version=VERSION,
            )

        print(
            f"    [nutrition] matched FoodItem={fooditem_name} "
            f"-> 樣品名稱={row.get('樣品名稱')} "
            f"({matched.matched_by}) | nutrients={len(nutrition_values)}"
        )

    def import_all_fooditem_nutrition(self) -> None:
        print("\nImporting FoodItem -> Nutrient ...")

        query = """
        MATCH (f:FoodItem)
        RETURN f.name AS name
        ORDER BY f.name
        """

        with self.driver.session() as session:
            rows = session.run(query)
            fooditems = [r["name"] for r in rows]

        print(f"Found {len(fooditems)} FoodItem node(s).")

        for fooditem_name in fooditems:
            self.upsert_fooditem_nutrition(fooditem_name)

    def import_disease_biomarker_rules(self) -> None:
        print("\nImporting Disease / Biomarker / Diet Rules ...")

        with self.driver.session() as session:
            session.run(
                """
                MERGE (s:Source {name: $source_name})
                SET s.type = $source_type
                """,
                source_name=DISEASE_RULE_SOURCE_NAME,
                source_type=DISEASE_RULE_SOURCE_TYPE,
            )

            session.run(
                """
                MERGE (s:Source {name: $source_name})
                SET s.type = $source_type
                """,
                source_name=BIOMARKER_LINK_SOURCE_NAME,
                source_type=BIOMARKER_LINK_SOURCE_TYPE,
            )

        disease_query = """
        MERGE (d:Disease {name: $disease_name})
        SET d.description = $description,
            d.created_by_version = $version

        MERGE (s:Source {name: $source_name})
        MERGE (d)-[:DEFINED_IN]->(s)

        WITH d
        UNWIND $biomarkers AS biomarker_name
        MERGE (b:Biomarker {name: biomarker_name})
        ON CREATE SET b.created_by_version = $version
        MERGE (d)-[r:AFFECTS]->(b)
        SET r.source = $source_name,
            r.version = $version
        """

        rule_query = """
        MERGE (d:Disease {name: $disease_name})
        MERGE (n:Nutrient {name: $nutrient_name})
        ON CREATE SET n.created_by_version = $version

        MERGE (d)-[r:HAS_DIET_RULE]->(n)
        SET r.rule_type = $rule_type,
            r.min_value = $min_value,
            r.max_value = $max_value,
            r.unit = $unit,
            r.label = $label,
            r.note = $note,
            r.version = $version,
            r.source = $source_name
        """

        biomarker_nutrient_query = """
        MERGE (b:Biomarker {name: $biomarker_name})
        ON CREATE SET b.created_by_version = $version

        MERGE (n:Nutrient {name: $nutrient_name})
        ON CREATE SET n.created_by_version = $version

        MERGE (n)-[r:AFFECTS_BIOMARKER]->(b)
        SET r.relation = $relation,
            r.effect = $effect,
            r.version = $version,
            r.source = $source_name
        """

        with self.driver.session() as session:
            for disease in self.disease_rules:
                session.run(
                    disease_query,
                    disease_name=disease["disease"],
                    description=disease.get("description"),
                    biomarkers=disease.get("biomarkers", []),
                    source_name=DISEASE_RULE_SOURCE_NAME,
                    version=VERSION,
                )

                for rule in disease.get("rules", []):
                    session.run(
                        rule_query,
                        disease_name=disease["disease"],
                        nutrient_name=rule["nutrient"],
                        rule_type=rule.get("rule_type"),
                        min_value=rule.get("min"),
                        max_value=rule.get("max"),
                        unit=rule.get("unit"),
                        label=rule.get("label"),
                        note=rule.get("note"),
                        source_name=DISEASE_RULE_SOURCE_NAME,
                        version=VERSION,
                    )

            for link in self.biomarker_links:
                session.run(
                    biomarker_nutrient_query,
                    biomarker_name=link["biomarker"],
                    nutrient_name=link["nutrient"],
                    relation=link["relation"],
                    effect=link["effect"],
                    source_name=BIOMARKER_LINK_SOURCE_NAME,
                    version=VERSION,
                )

        print(f"Imported {len(self.disease_rules)} disease seed(s).")
        print(
            f"Imported {len(self.biomarker_links)} biomarker-nutrient link(s).")

    def print_suggested_queries(self) -> None:
        print("\nSuggested Neo4j queries:")
        print("-" * 72)
        print(
            """
// 主展示鏈：Dish -> Ingredient -> FoodItem -> Nutrient -> Biomarker
MATCH p =
(d:Dish {name: "宮保雞丁"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(f:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
RETURN p
            """.strip()
        )
        print("-" * 72)
        print(
            """
// 若你不想顯示 FoodItem，可改成只回傳 d, i, n, b
MATCH
(d:Dish {name: "宮保雞丁"})
-[:CONTAINS]->
(i:Ingredient)
-[:MAP_TO]->
(:FoodItem)
-[:HAS_NUTRIENT]->
(n:Nutrient)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
RETURN d, i, n, b
            """.strip()
        )
        print("-" * 72)

    def run(self) -> None:
        self.create_schema()
        self.load_ingredient_mapping()
        self.load_nutrition_data()
        self.load_disease_rule_json()
        self.load_biomarker_link_json()

        recipes = self.load_test_recipes()

        for recipe in recipes:
            print("=" * 72)
            print(
                f"Processing recipe: {recipe.get('recipe_id')} | {recipe.get('name')}")

            for ing in recipe.get("ingredients", []):
                original_name = (ing.get("name") or "").strip()
                raw_name = ing.get("name_raw")
                mapping = self.resolve_mapping(original_name, raw_name)

                print(
                    f"  - ingredient={original_name} | raw={raw_name} | "
                    f"mapped_ingredient={mapping.ingredient_name} | "
                    f"fooditem={mapping.fooditem_name} | "
                    f"matched={mapping.matched} | "
                    f"confidence={mapping.confidence}"
                )

            self.insert_recipe(recipe)

        self.import_all_fooditem_nutrition()
        self.import_disease_biomarker_rules()
        self.print_suggested_queries()

        print("\nAll selected data inserted successfully.")


if __name__ == "__main__":
    builder = KGBuilderV61()
    try:
        builder.run()
    finally:
        builder.close()
