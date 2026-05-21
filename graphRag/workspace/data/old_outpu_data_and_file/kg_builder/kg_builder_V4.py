"""
kg_builder.py

Version History
---------------
V4 (2026-04-11)

[Added]
- 支援讀取 ingredient_mapping.json
- 建立 Ingredient -> FoodItem -> MAP_TO 關係
- 新增 FoodItem 與 Source 節點 schema
- 支援多種 ingredient_mapping.json 格式
- 若找不到 mapping，支援 fallback self-mapping
- 匯入時記錄 mapping confidence 與 mapping source

[Changed]
- Dish 節點改以 recipe_id 作為唯一鍵，避免同名料理衝突
- 匯入流程改為同時處理 recipe source 與 ingredient mapping
- console log 增加 mapping 結果顯示

[Removed]
- 無

[Fixed]
- 修正只以 dish name 當唯一鍵可能造成覆蓋的問題

[Notes]
- 本版本完成：
  Dish -> Ingredient -> FoodItem
- 尚未完成：
  FoodItem -> Nutrient
  Nutrient -> Biomarker -> Disease
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

from neo4j import GraphDatabase


# =========================
# 版本資訊
# =========================
VERSION = "V4"


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


# =========================
# 路徑設定
# =========================
BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"

RECIPES_PATH = DATA_DIR / "recipes.json"
INGREDIENT_MAPPING_PATH = DATA_DIR / "ingredient_mapping.json"


# =========================
# 測試用（只跑幾筆）
# 設成空集合代表全跑
# =========================
TEST_RECIPE_IDS = {
    "r481005",  # 洋蔥鱸魚豆腐湯
    "r481002",  # 義式千層麵
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
    def safe_float(value: Any, default: float = 0.0) -> float:
        try:
            if value is None:
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
    # 支援多種格式
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

        # 格式 1:
        # {
        #   "雞丁": "雞肉(去皮)",
        #   "醬汁": "醬油"
        # }
        if isinstance(raw, dict) and all(not isinstance(v, (dict, list)) for v in raw.values()):
            for ingredient_key, fooditem_value in raw.items():
                norm_key = self.normalize_key(ingredient_key)
                lookup[norm_key] = {
                    "ingredient_name": str(ingredient_key).strip(),
                    "fooditem_name": str(fooditem_value).strip(),
                    "confidence": 1.0,
                    "mapping_source": "ingredient_mapping.json:direct_dict",
                }

        # 格式 2:
        # {
        #   "雞丁": {
        #       "ingredient_name": "雞肉",
        #       "fooditem_name": "雞肉(去皮)",
        #       "confidence": 0.95
        #   }
        # }
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
                        "confidence": confidence,
                        "mapping_source": "ingredient_mapping.json:nested_dict",
                    }

                    aliases = value.get("aliases", [])
                    if isinstance(aliases, list):
                        for alias in aliases:
                            alias_key = self.normalize_key(alias)
                            lookup[alias_key] = {
                                "ingredient_name": str(ingredient_name).strip(),
                                "fooditem_name": str(fooditem_name).strip(),
                                "confidence": confidence,
                                "mapping_source": "ingredient_mapping.json:alias_list",
                            }

        # 格式 3:
        # [
        #   {
        #     "ingredient_name": "雞丁",
        #     "canonical_ingredient": "雞肉",
        #     "fooditem_name": "雞肉(去皮)",
        #     "confidence": 0.95
        #   }
        # ]
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

    # =========================
    # mapping 查詢
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
                    confidence=self.safe_float(hit.get("confidence"), 1.0),
                    mapping_source=hit.get("mapping_source", MAPPING_SOURCE_NAME),
                    matched=True,
                )

        # fallback：自己對自己，確保流程可跑
        canonical = ingredient_name.strip()
        return MappingResult(
            ingredient_name=canonical,
            fooditem_name=canonical,
            confidence=0.0,
            mapping_source="fallback_self_mapping",
            matched=False,
        )

    # =========================
    # 寫入單筆 recipe
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
    # 主流程
    # =========================
    def run(self) -> None:
        self.create_schema()
        self.load_ingredient_mapping()
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