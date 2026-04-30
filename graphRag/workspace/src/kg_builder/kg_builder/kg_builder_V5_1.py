"""
kg_builder.py

Version History
---------------
V5 (2026-04-11)

[Added]
- 支援讀取 nutrition_data.json
- 建立 FoodItem -> Nutrient -> HAS_NUTRIENT 關係
- 新增 Nutrient 節點 schema
- 新增 nutrition source 節點
- 支援從 nutrition_data.json 依樣品名稱建立 nutrition lookup
- 匯入時自動將 FoodItem 與 nutrition record 對接
- HAS_NUTRIENT 關係加入 amount / unit / source_field / builder_version

[Changed]
- 匯入流程改為同時處理：
  Dish -> Ingredient
  Ingredient -> FoodItem
  FoodItem -> Nutrient
- console log 增加 nutrition matching 結果顯示

[Removed]
- 無

[Fixed]
- 修正 FoodItem 僅建立節點但尚未附帶營養資訊的問題

[Notes]
- 本版本完成：
  Dish -> Ingredient -> FoodItem -> Nutrient
- nutrition_data.json 目前以「樣品名稱」作為主要對接鍵
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
from dotenv import load_dotenv


def _load_env_files() -> None:
    # 這裡的路徑設定為工作區 root 的 .env
    # 結構: workspace/src/test1/kg_builder_V5.py -> parents[2] 是 workspace/
    env_path = Path(__file__).resolve().parents[2] / ".env"
    if env_path.exists():
        load_dotenv(env_path)
        print(f"[KG Builder] Loaded env from: {env_path}")
    else:
        print("[KG Builder] WARNING: .env file not found.")


_load_env_files()


# =========================
# 版本資訊
# =========================
VERSION = "V5"


# =========================
# 環境設定
# =========================
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
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
# 這裡修改為實際資料所在的 src/test2 路徑
BASE_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = BASE_DIR.parents[1]
DATA_DIR = WORKSPACE_ROOT / "src" / "test2" / "data" / "input"

RECIPES_PATH = DATA_DIR / "recipes.json"
INGREDIENT_MAPPING_PATH = DATA_DIR / "ingredient_mapping.json"
NUTRITION_DATA_PATH = DATA_DIR / "nutrition_data.json"


# =========================
# 測試用（空集合代表全跑）
# =========================
TEST_RECIPE_IDS = {
    "r481005",  # 洋蔥鱸魚豆腐湯
    "r481002",  # 義式千層麵
}


# =========================
# 要匯入的營養欄位
# nutrition_data.json 中欄位名稱可直接對應 
# =========================
NUTRIENT_FIELD_SPECS: List[Tuple[str, str, str]] = [
    ("熱量", "熱量(kcal)", "kcal"),
    ("蛋白質", "粗蛋白(g)", "g"),
    ("脂肪", "粗脂肪(g)", "g"),
    ("飽和脂肪", "飽和脂肪(g)", "g"),
    ("碳水化合物", "總碳水化合物(g)", "g"),
    ("膳食纖維", "膳食纖維(g)", "g"),
    ("糖", "糖質總量(g)", "g"),
    ("鈉", "鈉(mg)", "mg"),
    ("鉀", "鉀(mg)", "mg"),
    ("鈣", "鈣(mg)", "mg"),
    ("鎂", "鎂(mg)", "mg"),
    ("鐵", "鐵(mg)", "mg"),
    ("鋅", "鋅(mg)", "mg"),
    ("磷", "磷(mg)", "mg"),
    ("維生素C", "維生素C(mg)", "mg"),
    ("膽固醇", "膽固醇(mg)", "mg"),
]


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
    fooditem_name: str
    matched_name: Optional[str]
    matched: bool
    nutrition_values: List[Dict[str, Any]]


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
        self.nutrition_lookup: Dict[str, Dict[str, Any]] = {}

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
            if value is None:
                return default
            if value == "":
                return default
            return float(value)
        except (TypeError, ValueError):
            return default

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
    # 讀取 recipes.json
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
    # 讀取 ingredient_mapping.json
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
                norm_key = self.normalize_key(ingredient_key)
                lookup[norm_key] = {
                    "ingredient_name": str(ingredient_key).strip(),
                    "fooditem_name": str(fooditem_value).strip(),
                    "confidence": 1.0,
                    "mapping_source": "ingredient_mapping.json:direct_dict",
                }

        elif isinstance(raw, dict):
            for ingredient_key, value in raw.items():
                norm_key = self.normalize_key(ingredient_key)

                if isinstance(value, dict):
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
                        "confidence": confidence if confidence is not None else 1.0,
                        "mapping_source": "ingredient_mapping.json:nested_dict",
                    }

                    aliases = value.get("aliases", [])
                    if isinstance(aliases, list):
                        for alias in aliases:
                            alias_key = self.normalize_key(alias)
                            lookup[alias_key] = {
                                "ingredient_name": str(ingredient_name).strip(),
                                "fooditem_name": str(fooditem_name).strip(),
                                "confidence": confidence if confidence is not None else 1.0,
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
                    "confidence": confidence if confidence is not None else 1.0,
                    "mapping_source": "ingredient_mapping.json:list",
                }

                aliases = item.get("aliases", [])
                if isinstance(aliases, list):
                    for alias in aliases:
                        lookup[self.normalize_key(alias)] = {
                            "ingredient_name": str(ingredient_name).strip(),
                            "fooditem_name": str(fooditem_name).strip(),
                            "confidence": confidence if confidence is not None else 1.0,
                            "mapping_source": "ingredient_mapping.json:list_alias",
                        }

        else:
            print("WARNING: ingredient_mapping.json format not recognized. Will use fallback self-mapping.")

        self.mapping_lookup = lookup
        print(f"Loaded {len(self.mapping_lookup)} mapping key(s).")

    # =========================
    # 讀取 nutrition_data.json
    # nutrition_data.json 中「樣品名稱」可當主對接鍵 
    # =========================
    def load_nutrition_data(self) -> None:
        print(f"Loading nutrition data from: {NUTRITION_DATA_PATH}")

        if not NUTRITION_DATA_PATH.exists():
            print("WARNING: nutrition_data.json not found. Nutrition import will be skipped.")
            self.nutrition_lookup = {}
            return

        with open(NUTRITION_DATA_PATH, "r", encoding="utf-8") as f:
            raw = json.load(f)

        if not isinstance(raw, list):
            raise ValueError("nutrition_data.json must be a list of records")

        lookup: Dict[str, Dict[str, Any]] = {}

        for row in raw:
            if not isinstance(row, dict):
                continue

            sample_name = row.get("樣品名稱")
            if not sample_name:
                continue

            keys_to_register = {
                self.normalize_key(sample_name),
            }

            alias_text = row.get("俗名")
            if isinstance(alias_text, str) and alias_text.strip():
                for alias in alias_text.split(","):
                    alias_key = self.normalize_key(alias)
                    if alias_key:
                        keys_to_register.add(alias_key)

            for key in keys_to_register:
                if key and key not in lookup:
                    lookup[key] = row

        self.nutrition_lookup = lookup
        print(f"Loaded {len(self.nutrition_lookup)} nutrition lookup key(s).")

    # =========================
    # ingredient mapping
    # =========================
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
    # nutrition matching
    # =========================
    def resolve_nutrition(self, fooditem_name: str) -> NutritionMatchResult:
        key = self.normalize_key(fooditem_name)
        row = self.nutrition_lookup.get(key)

        if not row:
            return NutritionMatchResult(
                fooditem_name=fooditem_name,
                matched_name=None,
                matched=False,
                nutrition_values=[],
            )

        nutrition_values: List[Dict[str, Any]] = []

        for nutrient_name, source_field, unit in NUTRIENT_FIELD_SPECS:
            amount = self.safe_float(row.get(source_field), None)
            if amount is None:
                continue

            nutrition_values.append(
                {
                    "nutrient_name": nutrient_name,
                    "amount": amount,
                    "unit": unit,
                    "source_field": source_field,
                }
            )

        return NutritionMatchResult(
            fooditem_name=fooditem_name,
            matched_name=row.get("樣品名稱"),
            matched=True,
            nutrition_values=nutrition_values,
        )

    # =========================
    # 寫入單筆 recipe
    # =========================
    def insert_recipe(self, recipe: Dict[str, Any]) -> None:
        recipe_id = recipe.get("recipe_id")
        dish_name = recipe.get("name")
        servings = recipe.get("servings")

        prepared_ingredients: List[Dict[str, Any]] = []
        prepared_nutrition_rows: List[Dict[str, Any]] = []

        seen_fooditem_names = set()

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

            if mapping.fooditem_name not in seen_fooditem_names:
                seen_fooditem_names.add(mapping.fooditem_name)

                nutrition_match = self.resolve_nutrition(mapping.fooditem_name)

                if nutrition_match.matched:
                    for nv in nutrition_match.nutrition_values:
                        prepared_nutrition_rows.append(
                            {
                                "fooditem_name": mapping.fooditem_name,
                                "matched_name": nutrition_match.matched_name,
                                "nutrient_name": nv["nutrient_name"],
                                "amount": nv["amount"],
                                "unit": nv["unit"],
                                "source_field": nv["source_field"],
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

        MERGE (nutrition_source_node:Source {name: $nutrition_source_name})
        SET nutrition_source_node.type = $nutrition_source_type

        WITH d, mapping_source_node, nutrition_source_node

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

        WITH nutrition_source_node
        UNWIND $nutrition_rows AS nr
        MERGE (f:FoodItem {name: nr.fooditem_name})
        MERGE (n:Nutrient {name: nr.nutrient_name})
        ON CREATE SET n.created_by_version = $version

        MERGE (f)-[hn:HAS_NUTRIENT]->(n)
        SET hn.amount = nr.amount,
            hn.unit = nr.unit,
            hn.source_field = nr.source_field,
            hn.matched_name = nr.matched_name,
            hn.builder_version = $version

        MERGE (f)-[:DERIVED_FROM]->(nutrition_source_node)
        """

        with self.driver.session() as session:
            session.run(
                query,
                recipe_id=recipe_id,
                dish_name=dish_name,
                servings=servings,
                ingredients=prepared_ingredients,
                nutrition_rows=prepared_nutrition_rows,
                recipe_source_name=RECIPE_SOURCE_NAME,
                recipe_source_type=RECIPE_SOURCE_TYPE,
                mapping_source_name=MAPPING_SOURCE_NAME,
                mapping_source_type=MAPPING_SOURCE_TYPE,
                nutrition_source_name=NUTRITION_SOURCE_NAME,
                nutrition_source_type=NUTRITION_SOURCE_TYPE,
                version=VERSION,
            )

    # =========================
    # 主流程
    # =========================
    def run(self) -> None:
        self.create_schema()
        self.load_ingredient_mapping()
        self.load_nutrition_data()
        recipes = self.load_test_recipes()

        for recipe in recipes:
            print("=" * 80)
            print(f"Processing recipe: {recipe.get('recipe_id')} | {recipe.get('name')}")

            seen_fooditems = set()

            for ing in recipe.get("ingredients", []):
                original_name = (ing.get("name") or "").strip()
                raw_name = ing.get("name_raw")
                mapping = self.resolve_mapping(original_name, raw_name)

                line = (
                    f"  - ingredient={original_name} | raw={raw_name} | "
                    f"mapped_ingredient={mapping.ingredient_name} | "
                    f"fooditem={mapping.fooditem_name} | "
                    f"matched_mapping={mapping.matched} | "
                    f"confidence={mapping.confidence}"
                )

                if mapping.fooditem_name not in seen_fooditems:
                    seen_fooditems.add(mapping.fooditem_name)
                    nutrition_match = self.resolve_nutrition(mapping.fooditem_name)
                    line += (
                        f" | matched_nutrition={nutrition_match.matched}"
                    )
                    if nutrition_match.matched:
                        line += f" | nutrition_name={nutrition_match.matched_name} | nutrient_count={len(nutrition_match.nutrition_values)}"

                print(line)

            self.insert_recipe(recipe)

        print("\nAll selected recipes inserted successfully.")

    # =========================
    # 可選：清空資料（測試時手動呼叫）
    # =========================
    def clear_graph(self) -> None:
        with self.driver.session() as session:
            session.run("MATCH (n) DETACH DELETE n")
        print("Graph cleared.")


# =========================
# 執行
# =========================
if __name__ == "__main__":
    builder = KGBuilder()
    try:
        builder.run()
    finally:
        builder.close()