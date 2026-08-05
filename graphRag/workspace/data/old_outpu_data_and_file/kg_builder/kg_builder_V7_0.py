"""
kg_builder_V7.py

Version History
---------------
V7 (2026-04-26)

[Added]
- 改為正式主圖結構：Dish -> Ingredient -> Nutrition -> Biomarker
- 新增 Nutrition 節點，取代 V5/V6 的 Nutrient 節點命名
- Ingredient 直接建立 HAS_NUTRITION 關係，不再透過 FoodItem 節點
- Ingredient 節點保留 matched_food_name、matched_food_id、nutrition_match_by 等屬性，用於追溯 nutrition_data.json 對應結果
- 支援 disease_rules.json 與 biomarker_nutrition_links.json / biomarker_nutrient_links.json
- 新增 Source 節點，但只作為 provenance，不進入主展示鏈
- 新增查詢提示，主鏈為 Dish -> Ingredient -> Nutrition -> Biomarker

[Changed]
- 移除 FoodItem 作為主圖節點的角色
- 將 V6.1 的 Nutrient -> Biomarker 改為 Nutrition -> Biomarker
- 將 ingredient mapping 視為「對應營養資料庫列」的輔助資料，而不是圖上的中繼節點
- Disease rule 的目標節點改為 Nutrition

[Removed]
- 不再建立 (:FoodItem)
- 不再建立 (:Ingredient)-[:MAP_TO]->(:FoodItem)
- 不再建立 (:FoodItem)-[:HAS_NUTRIENT]->(:Nutrient)

[Notes]
- 正式主鏈：
  (:Dish)-[:CONTAINS]->(:Ingredient)-[:HAS_NUTRITION]->(:Nutrition)-[:AFFECTS_BIOMARKER]->(:Biomarker)

- 背景規則鏈：
  (:Disease)-[:HAS_DIET_RULE]->(:Nutrition)
  (:Disease)-[:AFFECTS]->(:Biomarker)

- 若你過去已匯入 V4/V5/V6 資料，建議先清空 Neo4j 再跑 V7：
  MATCH (n) DETACH DELETE n;
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from neo4j import GraphDatabase


# =========================
# Version
# =========================
VERSION = "V7"


# =========================
# Neo4j Environment
# =========================
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")


# =========================
# Source Names
# =========================
RECIPE_SOURCE_NAME = "recipes.json"
RECIPE_SOURCE_TYPE = "recipe_file"

MAPPING_SOURCE_NAME = "ingredient_mapping.json"
MAPPING_SOURCE_TYPE = "mapping_file"

NUTRITION_SOURCE_NAME = "nutrition_data.json"
NUTRITION_SOURCE_TYPE = "nutrition_file"

DISEASE_RULE_SOURCE_NAME = "disease_rules.json"
DISEASE_RULE_SOURCE_TYPE = "manual_rule_seed"

BIOMARKER_LINK_SOURCE_NAME = "biomarker_nutrition_links.json"
BIOMARKER_LINK_SOURCE_TYPE = "manual_rule_seed"


# =========================
# Paths
# =========================
BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"

RECIPES_PATH = DATA_DIR / "recipes.json"
INGREDIENT_MAPPING_PATH = DATA_DIR / "ingredient_mapping.json"
NUTRITION_DATA_PATH = Path(
    r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json")
DISEASE_RULES_PATH = DATA_DIR / "disease_rules.json"

# 優先使用 nutrition 命名；若不存在，兼容你前一版的 nutrient 檔名
BIOMARKER_NUTRITION_LINKS_PATH = DATA_DIR / "biomarker_nutrition_links.json"
BIOMARKER_NUTRIENT_LINKS_PATH = DATA_DIR / "biomarker_nutrient_links.json"


# =========================
# Test Recipes
# 設成空集合 set() 代表全部匯入
# =========================
TEST_RECIPE_IDS = {
    "r481002",  # 義式千層麵
    "r481005",  # 洋蔥鱸魚豆腐湯
}


# =========================
# Nutrition field whitelist
# key = nutrition_data.json 欄位名
# value = (Nutrition node name, unit)
# =========================
NUTRITION_FIELD_MAP: Dict[str, Tuple[str, str]] = {
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
# Data Classes
# =========================
@dataclass
class MappingResult:
    ingredient_name: str
    matched_food_name: str
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
# KG Builder V7
# =========================
class KGBuilderV7:
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

    # =========================
    # Utility
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
        for sep in [",", "，", ";", "；", "/", "、"]:
            raw = raw.replace(sep, "|")

        return [x.strip() for x in raw.split("|") if x.strip()]

    @staticmethod
    def load_json_file(path: Path, label: str) -> Any:
        if not path.exists():
            raise FileNotFoundError(f"{label} not found: {path}")
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)

    # =========================
    # Schema
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
            FOR (n:Nutrition) REQUIRE n.name IS UNIQUE
            """,
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (b:Biomarker) REQUIRE b.name IS UNIQUE
            """,
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (d:Disease) REQUIRE d.name IS UNIQUE
            """,
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (s:Source) REQUIRE s.name IS UNIQUE
            """,
            """
            CREATE INDEX IF NOT EXISTS
            FOR (d:Dish) ON (d.name)
            """,
            """
            CREATE INDEX IF NOT EXISTS
            FOR (i:Ingredient) ON (i.matched_food_name)
            """,
            """
            CREATE INDEX IF NOT EXISTS
            FOR (n:Nutrition) ON (n.name)
            """,
        ]

        with self.driver.session() as session:
            for query in queries:
                session.run(query)

        print("Schema ready.")

    # =========================
    # Load recipes.json
    # =========================
    def load_recipes(self) -> List[Dict[str, Any]]:
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

    # =========================
    # Load ingredient_mapping.json
    # =========================
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

        # 格式 1:
        # {"雞丁": "雞肉", "披薩起士絲": "起司"}
        if isinstance(raw, dict) and all(not isinstance(v, (dict, list)) for v in raw.values()):
            for ingredient_key, food_value in raw.items():
                lookup[self.normalize_key(ingredient_key)] = {
                    "ingredient_name": str(ingredient_key).strip(),
                    "matched_food_name": str(food_value).strip(),
                    "confidence": 1.0,
                    "mapping_source": "ingredient_mapping.json:direct_dict",
                }

        # 格式 2:
        # {"雞丁": {"ingredient_name": "雞丁", "fooditem_name": "雞肉", "confidence": 0.95}}
        elif isinstance(raw, dict):
            for ingredient_key, value in raw.items():
                if not isinstance(value, dict):
                    continue

                ingredient_name = (
                    value.get("ingredient_name")
                    or value.get("canonical_ingredient")
                    or value.get("name")
                    or ingredient_key
                )

                matched_food_name = (
                    value.get("matched_food_name")
                    or value.get("fooditem_name")
                    or value.get("food_item")
                    or value.get("fooditem")
                    or value.get("mapped_to")
                    or value.get("nutrition_sample_name")
                    or ingredient_name
                )

                confidence = self.safe_float(value.get("confidence"), 1.0)

                item = {
                    "ingredient_name": str(ingredient_name).strip(),
                    "matched_food_name": str(matched_food_name).strip(),
                    "confidence": confidence,
                    "mapping_source": "ingredient_mapping.json:nested_dict",
                }

                lookup[self.normalize_key(ingredient_key)] = item

                aliases = value.get("aliases", [])
                if isinstance(aliases, list):
                    for alias in aliases:
                        lookup[self.normalize_key(alias)] = item

        # 格式 3:
        # [{"ingredient_name": "雞丁", "fooditem_name": "雞肉", "aliases": [...]}]
        elif isinstance(raw, list):
            for value in raw:
                if not isinstance(value, dict):
                    continue

                source_name = (
                    value.get("source_name")
                    or value.get("raw_name")
                    or value.get("ingredient_name")
                    or value.get("ingredient")
                    or value.get("name")
                )

                if not source_name:
                    continue

                ingredient_name = (
                    value.get("canonical_ingredient")
                    or value.get("ingredient_name")
                    or value.get("ingredient")
                    or value.get("name")
                    or source_name
                )

                matched_food_name = (
                    value.get("matched_food_name")
                    or value.get("fooditem_name")
                    or value.get("food_item")
                    or value.get("fooditem")
                    or value.get("mapped_to")
                    or value.get("nutrition_sample_name")
                    or ingredient_name
                )

                confidence = self.safe_float(value.get("confidence"), 1.0)

                item = {
                    "ingredient_name": str(ingredient_name).strip(),
                    "matched_food_name": str(matched_food_name).strip(),
                    "confidence": confidence,
                    "mapping_source": "ingredient_mapping.json:list",
                }

                lookup[self.normalize_key(source_name)] = item

                aliases = value.get("aliases", [])
                if isinstance(aliases, list):
                    for alias in aliases:
                        lookup[self.normalize_key(alias)] = item

        else:
            print(
                "WARNING: ingredient_mapping.json format not recognized. Will use fallback self-mapping.")

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
                    ingredient_name=str(hit["ingredient_name"]).strip(),
                    matched_food_name=str(hit["matched_food_name"]).strip(),
                    confidence=float(hit.get("confidence", 1.0)),
                    mapping_source=str(
                        hit.get("mapping_source", MAPPING_SOURCE_NAME)),
                    matched=True,
                )

        canonical = ingredient_name.strip()
        return MappingResult(
            ingredient_name=canonical,
            matched_food_name=canonical,
            confidence=0.0,
            mapping_source="fallback_self_mapping",
            matched=False,
        )

    # =========================
    # Load nutrition_data.json
    # =========================
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

            for alias in self.split_aliases(row.get("俗名")):
                by_alias[self.normalize_key(alias)] = row

        self.nutrition_by_name = by_name
        self.nutrition_by_alias = by_alias

        print(
            f"Loaded nutrition rows: {len(rows)} | "
            f"name keys: {len(self.nutrition_by_name)} | "
            f"alias keys: {len(self.nutrition_by_alias)}"
        )

    def resolve_nutrition_row(self, matched_food_name: str) -> NutritionMatchResult:
        key = self.normalize_key(matched_food_name)

        if key in self.nutrition_by_name:
            return NutritionMatchResult(
                matched=True,
                row=self.nutrition_by_name[key],
                matched_by="樣品名稱",
                matched_key=matched_food_name,
            )

        if key in self.nutrition_by_alias:
            return NutritionMatchResult(
                matched=True,
                row=self.nutrition_by_alias[key],
                matched_by="俗名",
                matched_key=matched_food_name,
            )

        return NutritionMatchResult(
            matched=False,
            row=None,
            matched_by="",
            matched_key="",
        )

    # =========================
    # Load disease_rules.json
    # =========================
    def load_disease_rules(self) -> None:
        print(f"Loading disease rules from: {DISEASE_RULES_PATH}")

        if not DISEASE_RULES_PATH.exists():
            print("WARNING: disease_rules.json not found. Disease rules will be skipped.")
            self.disease_rules = []
            return

        self.disease_rules = self.load_json_file(
            DISEASE_RULES_PATH, "disease_rules.json")
        print(f"Loaded {len(self.disease_rules)} disease rule seed(s).")

    # =========================
    # Load biomarker links JSON
    # =========================
    def load_biomarker_links(self) -> None:
        if BIOMARKER_NUTRITION_LINKS_PATH.exists():
            path = BIOMARKER_NUTRITION_LINKS_PATH
            label = "biomarker_nutrition_links.json"
        elif BIOMARKER_NUTRIENT_LINKS_PATH.exists():
            path = BIOMARKER_NUTRIENT_LINKS_PATH
            label = "biomarker_nutrient_links.json"
        else:
            print(
                "WARNING: biomarker nutrition link json not found. Biomarker links will be skipped.")
            self.biomarker_links = []
            return

        print(f"Loading biomarker links from: {path}")
        self.biomarker_links = self.load_json_file(path, label)
        print(
            f"Loaded {len(self.biomarker_links)} biomarker-nutrition link(s).")

    # =========================
    # Insert Dish / Ingredient
    # =========================
    def insert_recipe_and_ingredients(self, recipe: Dict[str, Any]) -> List[Dict[str, Any]]:
        recipe_id = recipe.get("recipe_id")
        dish_name = recipe.get("name")
        servings = recipe.get("servings")

        prepared: List[Dict[str, Any]] = []

        for ing in recipe.get("ingredients", []):
            original_name = (ing.get("name") or "").strip()
            raw_name = ing.get("name_raw")

            mapping = self.resolve_mapping(original_name, raw_name)
            nutrition_match = self.resolve_nutrition_row(
                mapping.matched_food_name)

            matched_food_id = None
            matched_sample_name = None
            matched_category = None

            if nutrition_match.matched and nutrition_match.row:
                matched_food_id = nutrition_match.row.get("整合編號")
                matched_sample_name = nutrition_match.row.get("樣品名稱")
                matched_category = nutrition_match.row.get("食品分類")

            prepared.append(
                {
                    "ingredient_name": mapping.ingredient_name,
                    "name_raw": raw_name,
                    "amount": ing.get("amount_value"),
                    "unit": ing.get("amount_unit"),
                    "amount_note": ing.get("amount_note"),
                    "matched_food_name": mapping.matched_food_name,
                    "matched_food_id": matched_food_id,
                    "matched_sample_name": matched_sample_name,
                    "matched_category": matched_category,
                    "mapping_confidence": mapping.confidence,
                    "mapping_source": mapping.mapping_source,
                    "nutrition_matched": nutrition_match.matched,
                    "nutrition_match_by": nutrition_match.matched_by,
                    "nutrition_match_key": nutrition_match.matched_key,
                }
            )

        query = """
        MERGE (d:Dish {recipe_id: $recipe_id})
        SET d.name = $dish_name,
            d.servings = $servings,
            d.builder_version = $version

        MERGE (recipe_source:Source {name: $recipe_source_name})
        SET recipe_source.type = $recipe_source_type

        MERGE (mapping_source_node:Source {name: $mapping_source_name})
        SET mapping_source_node.type = $mapping_source_type

        MERGE (nutrition_source_node:Source {name: $nutrition_source_name})
        SET nutrition_source_node.type = $nutrition_source_type

        MERGE (d)-[:EXTRACTED_FROM]->(recipe_source)

        WITH d, mapping_source_node, nutrition_source_node
        UNWIND $ingredients AS ing

        MERGE (i:Ingredient {name: ing.ingredient_name})
        ON CREATE SET i.created_by_version = $version

        SET i.matched_food_name = ing.matched_food_name,
            i.matched_food_id = ing.matched_food_id,
            i.matched_sample_name = ing.matched_sample_name,
            i.matched_category = ing.matched_category,
            i.mapping_confidence = ing.mapping_confidence,
            i.mapping_source = ing.mapping_source,
            i.nutrition_matched = ing.nutrition_matched,
            i.nutrition_match_by = ing.nutrition_match_by,
            i.nutrition_match_key = ing.nutrition_match_key,
            i.updated_by_version = $version

        MERGE (d)-[c:CONTAINS]->(i)
        SET c.amount = ing.amount,
            c.unit = ing.unit,
            c.amount_note = ing.amount_note,
            c.name_raw = ing.name_raw

        MERGE (i)-[:MAPPED_FROM]->(mapping_source_node)
        MERGE (i)-[:NUTRITION_DERIVED_FROM]->(nutrition_source_node)
        """

        with self.driver.session() as session:
            session.run(
                query,
                recipe_id=recipe_id,
                dish_name=dish_name,
                servings=servings,
                ingredients=prepared,
                recipe_source_name=RECIPE_SOURCE_NAME,
                recipe_source_type=RECIPE_SOURCE_TYPE,
                mapping_source_name=MAPPING_SOURCE_NAME,
                mapping_source_type=MAPPING_SOURCE_TYPE,
                nutrition_source_name=NUTRITION_SOURCE_NAME,
                nutrition_source_type=NUTRITION_SOURCE_TYPE,
                version=VERSION,
            )

        return prepared

    # =========================
    # Ingredient -> Nutrition
    # =========================
    def upsert_ingredient_nutrition(self, ingredient_name: str, matched_food_name: str) -> None:
        nutrition_match = self.resolve_nutrition_row(matched_food_name)

        if not nutrition_match.matched or not nutrition_match.row:
            print(
                f"    [nutrition] NOT FOUND for Ingredient={ingredient_name} | matched_food_name={matched_food_name}")
            return

        row = nutrition_match.row
        nutrition_values: List[Dict[str, Any]] = []

        for field_name, (nutrition_name, unit) in NUTRITION_FIELD_MAP.items():
            value = self.safe_float(row.get(field_name), None)
            if value is None:
                continue

            nutrition_values.append(
                {
                    "nutrition_name": nutrition_name,
                    "amount": value,
                    "unit": unit,
                    "source_field": field_name,
                }
            )

        if not nutrition_values:
            print(
                f"    [nutrition] matched but no usable nutrition fields for Ingredient={ingredient_name}")
            return

        query = """
        MATCH (i:Ingredient {name: $ingredient_name})

        MERGE (s:Source {name: $nutrition_source_name})
        SET s.type = $nutrition_source_type

        MERGE (i)-[:NUTRITION_DERIVED_FROM]->(s)

        WITH i
        UNWIND $nutrition_values AS nv

        MERGE (n:Nutrition {name: nv.nutrition_name})
        ON CREATE SET n.created_by_version = $version

        MERGE (i)-[r:HAS_NUTRITION]->(n)
        SET r.amount = nv.amount,
            r.unit = nv.unit,
            r.source_field = nv.source_field,
            r.source_food_name = $matched_food_name,
            r.source_food_id = $matched_food_id,
            r.source_sample_name = $matched_sample_name,
            r.nutrition_match_by = $nutrition_match_by,
            r.nutrition_match_key = $nutrition_match_key,
            r.data_version = $version
        """

        with self.driver.session() as session:
            session.run(
                query,
                ingredient_name=ingredient_name,
                matched_food_name=matched_food_name,
                matched_food_id=row.get("整合編號"),
                matched_sample_name=row.get("樣品名稱"),
                nutrition_match_by=nutrition_match.matched_by,
                nutrition_match_key=nutrition_match.matched_key,
                nutrition_source_name=NUTRITION_SOURCE_NAME,
                nutrition_source_type=NUTRITION_SOURCE_TYPE,
                nutrition_values=nutrition_values,
                version=VERSION,
            )

        print(
            f"    [nutrition] Ingredient={ingredient_name} "
            f"-> source_food={row.get('樣品名稱')} "
            f"({nutrition_match.matched_by}) | nutrition={len(nutrition_values)}"
        )

    def import_selected_ingredient_nutrition(self, prepared_ingredients: List[Dict[str, Any]]) -> None:
        seen = set()

        for ing in prepared_ingredients:
            ingredient_name = ing["ingredient_name"]
            matched_food_name = ing["matched_food_name"]

            key = (ingredient_name, matched_food_name)
            if key in seen:
                continue
            seen.add(key)

            self.upsert_ingredient_nutrition(
                ingredient_name, matched_food_name)

    # =========================
    # Disease / Biomarker / Rule
    # =========================
    @staticmethod
    def normalize_rule_nutrition_name(rule: Dict[str, Any]) -> str:
        return (
            rule.get("nutrition")
            or rule.get("nutrient")
            or rule.get("name")
            or ""
        )

    @staticmethod
    def normalize_link_nutrition_name(link: Dict[str, Any]) -> str:
        return (
            link.get("nutrition")
            or link.get("nutrient")
            or link.get("name")
            or ""
        )

    def import_disease_biomarker_rules(self) -> None:
        print("\nImporting Disease / Biomarker / Diet Rules ...")

        disease_query = """
        MERGE (d:Disease {name: $disease_name})
        SET d.description = $description,
            d.created_by_version = $version

        MERGE (s:Source {name: $source_name})
        SET s.type = $source_type

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
        MERGE (n:Nutrition {name: $nutrition_name})
        ON CREATE SET n.created_by_version = $version

        MERGE (s:Source {name: $source_name})
        SET s.type = $source_type

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

        biomarker_query = """
        MERGE (b:Biomarker {name: $biomarker_name})
        ON CREATE SET b.created_by_version = $version

        MERGE (n:Nutrition {name: $nutrition_name})
        ON CREATE SET n.created_by_version = $version

        MERGE (s:Source {name: $source_name})
        SET s.type = $source_type

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
                    disease_name=disease.get("disease"),
                    description=disease.get("description"),
                    biomarkers=disease.get("biomarkers", []),
                    source_name=DISEASE_RULE_SOURCE_NAME,
                    source_type=DISEASE_RULE_SOURCE_TYPE,
                    version=VERSION,
                )

                for rule in disease.get("rules", []):
                    nutrition_name = self.normalize_rule_nutrition_name(rule)
                    if not nutrition_name:
                        continue

                    session.run(
                        rule_query,
                        disease_name=disease.get("disease"),
                        nutrition_name=nutrition_name,
                        rule_type=rule.get("rule_type"),
                        min_value=rule.get("min"),
                        max_value=rule.get("max"),
                        unit=rule.get("unit"),
                        label=rule.get("label"),
                        note=rule.get("note"),
                        source_name=DISEASE_RULE_SOURCE_NAME,
                        source_type=DISEASE_RULE_SOURCE_TYPE,
                        version=VERSION,
                    )

            for link in self.biomarker_links:
                nutrition_name = self.normalize_link_nutrition_name(link)
                biomarker_name = link.get("biomarker")

                if not nutrition_name or not biomarker_name:
                    continue

                session.run(
                    biomarker_query,
                    biomarker_name=biomarker_name,
                    nutrition_name=nutrition_name,
                    relation=link.get("relation"),
                    effect=link.get("effect"),
                    source_name=BIOMARKER_LINK_SOURCE_NAME,
                    source_type=BIOMARKER_LINK_SOURCE_TYPE,
                    version=VERSION,
                )

        print(f"Imported {len(self.disease_rules)} disease seed(s).")
        print(
            f"Imported {len(self.biomarker_links)} biomarker-nutrition link(s).")

    # =========================
    # Suggested Queries
    # =========================
    def print_suggested_queries(self) -> None:
        print("\nSuggested Neo4j queries:")
        print("-" * 72)
        print(
            """
// 主展示鏈：Dish -> Ingredient -> Nutrition -> Biomarker
MATCH p =
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:HAS_NUTRITION]->
(n:Nutrition)
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
RETURN p
            """.strip()
        )
        print("-" * 72)
        print(
            """
// 所有 Ingredient 都顯示，後面沒接上也保留
MATCH (d:Dish {name: "義式千層麵"})-[:CONTAINS]->(i:Ingredient)
OPTIONAL MATCH (i)-[:HAS_NUTRITION]->(n:Nutrition)
OPTIONAL MATCH (n)-[:AFFECTS_BIOMARKER]->(b:Biomarker)
RETURN d, i, n, b
            """.strip()
        )
        print("-" * 72)

    # =========================
    # Main run
    # =========================
    def run(self) -> None:
        self.create_schema()
        self.load_ingredient_mapping()
        self.load_nutrition_data()
        self.load_disease_rules()
        self.load_biomarker_links()

        recipes = self.load_recipes()

        all_prepared: List[Dict[str, Any]] = []

        for recipe in recipes:
            print("=" * 72)
            print(
                f"Processing recipe: {recipe.get('recipe_id')} | {recipe.get('name')}")

            prepared = self.insert_recipe_and_ingredients(recipe)
            all_prepared.extend(prepared)

            for ing in prepared:
                print(
                    f"  - ingredient={ing.get('ingredient_name')} | "
                    f"raw={ing.get('name_raw')} | "
                    f"matched_food={ing.get('matched_food_name')} | "
                    f"nutrition_matched={ing.get('nutrition_matched')} | "
                    f"match_by={ing.get('nutrition_match_by')}"
                )

            self.import_selected_ingredient_nutrition(prepared)

        self.import_disease_biomarker_rules()
        self.print_suggested_queries()

        print("\nAll selected data inserted successfully.")


if __name__ == "__main__":
    builder = KGBuilderV7()
    try:
        builder.run()
    finally:
        builder.close()
