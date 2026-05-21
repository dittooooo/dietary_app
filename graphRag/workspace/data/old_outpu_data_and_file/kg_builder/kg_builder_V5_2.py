"""
kg_builder.py

Version History
---------------
V5 (2026-04-16)

[Added]
- 支援讀取 nutrition_data.json
- 建立 FoodItem -> Nutrient -> HAS_NUTRIENT 關係
- 新增 Nutrient 節點 schema
- 新增 nutrition data lookup（樣品名稱 / 俗名）
- 新增將 nutrition source 寫入 Source 節點
- 新增營養欄位白名單，避免把整份資料庫所有欄位都灌進圖譜
- 新增 nutrition matched / unmatched log

[Changed]
- 匯入流程改為：recipes -> ingredient mapping -> nutrition mapping
- FoodItem 建立後會嘗試自動對應 nutrition_data.json
- 將常用營養欄位統一轉成 Nutrient 節點 + HAS_NUTRIENT 關係屬性

[Removed]
- 無

[Fixed]
- 保留 V4 的 Dish.recipe_id 唯一鍵設計，避免 Dish.name 衝突
- nutrition_data.json 中 null / 空字串欄位不再寫入 Neo4j

[Notes]
- 本版本完成：
  Dish -> Ingredient -> FoodItem -> Nutrient
- 尚未完成：
  Nutrient -> Biomarker -> Disease
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from neo4j import GraphDatabase


# =========================
# 版本資訊
# =========================
VERSION = "V5"


# =========================
# 環境設定
# =========================
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")

RECIPE_SOURCE_NAME = "recipes.json"
RECIPE_SOURCE_TYPE = "recipe_file"

MAPPING_SOURCE_NAME = "ingredient_mapping.json"
MAPPING_SOURCE_TYPE = "mapping_file"

NUTRITION_SOURCE_NAME = "nutrition_data.json"
NUTRITION_SOURCE_TYPE = "nutrition_file"


# =========================
# 路徑設定
# =========================
BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"

RECIPES_PATH = DATA_DIR / "recipes.json"
INGREDIENT_MAPPING_PATH = DATA_DIR / "ingredient_mapping.json"
NUTRITION_DATA_PATH = DATA_DIR / "nutrition_data.json"


# =========================
# 測試用（設空集合代表全跑）
# =========================
TEST_RECIPE_IDS = {
    "r481005",  # 洋蔥鱸魚豆腐湯
    "r481002",  # 義式千層麵
}


# =========================
# 營養欄位白名單
# key = nutrition_data.json 欄位名
# value = (Nutrient name, unit)
# =========================
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


# =========================
# 資料結構
# =========================
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


# =========================
# 主類別
# =========================
class KGBuilder:
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

    def close(self) -> None:
        self.driver.close()

    # =========================
    # 工具函式
    # =========================
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
        seps = [",", "，", ";", "；", "/", "、"]
        for sep in seps:
            raw = raw.replace(sep, "|")
        return [x.strip() for x in raw.split("|") if x.strip()]

    # =========================
    # 建立 Schema
    # =========================
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
            CREATE INDEX IF NOT EXISTS
            FOR (d:Dish) ON (d.name)
            """,
        ]

        with self.driver.session() as session:
            for query in queries:
                session.run(query)

        print("Schema ready.")

    # =========================
    # recipes.json
    # =========================
    def load_test_recipes(self) -> List[Dict[str, Any]]:
        print(f"Loading recipes from: {RECIPES_PATH}")

        if not RECIPES_PATH.exists():
            raise FileNotFoundError(f"recipes.json not found: {RECIPES_PATH}")

        with open(RECIPES_PATH, "r", encoding="utf-8") as f:
            recipes = json.load(f)

        if TEST_RECIPE_IDS:
            selected = [r for r in recipes if r.get("recipe_id") in TEST_RECIPE_IDS]
        else:
            selected = recipes

        print(f"Loaded {len(selected)} recipe(s):")
        for recipe in selected:
            print(f"- {recipe.get('recipe_id')} | {recipe.get('name')}")

        return selected

    # =========================
    # ingredient_mapping.json
    # =========================
    def load_ingredient_mapping(self) -> None:
        print(f"Loading ingredient mapping from: {INGREDIENT_MAPPING_PATH}")

        if not INGREDIENT_MAPPING_PATH.exists():
            print("WARNING: ingredient_mapping.json not found. Will use fallback self-mapping.")
            self.mapping_lookup = {}
            return

        with open(INGREDIENT_MAPPING_PATH, "r", encoding="utf-8") as f:
            raw = json.load(f)

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

        else:
            print("WARNING: ingredient_mapping.json format not recognized. Will use fallback self-mapping.")

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
                    mapping_source=hit.get("mapping_source", MAPPING_SOURCE_NAME),
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

    # =========================
    # nutrition_data.json
    # =========================
    def load_nutrition_data(self) -> None:
        print(f"Loading nutrition data from: {NUTRITION_DATA_PATH}")

        if not NUTRITION_DATA_PATH.exists():
            print("WARNING: nutrition_data.json not found. Nutrition import will be skipped.")
            self.nutrition_by_name = {}
            self.nutrition_by_alias = {}
            return

        with open(NUTRITION_DATA_PATH, "r", encoding="utf-8") as f:
            rows = json.load(f)

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

    # =========================
    # Dish / Ingredient / FoodItem
    # =========================
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

    # =========================
    # FoodItem -> Nutrient
    # =========================
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
            print(f"    [nutrition] matched but no usable nutrient fields for FoodItem={fooditem_name}")
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

    # =========================
    # 主流程
    # =========================
    def run(self) -> None:
        self.create_schema()
        self.load_ingredient_mapping()
        self.load_nutrition_data()

        recipes = self.load_test_recipes()

        for recipe in recipes:
            print("=" * 72)
            print(f"Processing recipe: {recipe.get('recipe_id')} | {recipe.get('name')}")

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
        print("\nAll selected recipes inserted successfully.")


# =========================
# 執行
# =========================
if __name__ == "__main__":
    builder = KGBuilder()
    try:
        builder.run()
    finally:
        builder.close()