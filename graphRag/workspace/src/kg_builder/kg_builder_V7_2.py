"""
kg_builder_V7_2.py

Version History
---------------
V7.2 (2026-04-26)

[Added]
- 自動匯入 nutrition_data.json 中所有可轉成數值的營養欄位
- 新增 CORE_NUTRITION_NAMES，標記核心營養 is_core=True
- 新增 nutrition_category，自動分類：
  basic / mineral / vitamin / fatty_acid / amino_acid / sugar / other
- 主展示圖可只查核心營養
- 保留完整營養資料於 Ingredient -> Nutrition 的 HAS_NUTRITION 關係上
- 新增 suggested query：核心主鏈、完整營養表格、特定 Ingredient 完整營養

[Changed]
- 不再使用固定 NUTRITION_FIELD_MAP 白名單匯入營養
- Nutrition 節點名稱由 nutrition_data.json 欄位自動解析
- unit 由欄位括號自動解析，例如 鈉(mg) -> mg/100g
- 原始欄位名稱保留於 HAS_NUTRITION.source_field

[Removed]
- 移除營養欄位白名單匯入限制

[Notes]
- 資料層：全部營養欄位匯入
- 展示層：建議只查 is_core=True 的 Nutrition
- 若你已跑過舊版本，建議先清空 Neo4j：
  MATCH (n) DETACH DELETE n;
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional


# 若你的環境是 neo4j package
from neo4j import GraphDatabase


VERSION = "V7.2"


# =========================
# Neo4j Environment
# =========================
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")


# =========================
# Source as properties only
# 不再建立 Source 節點
# =========================
RECIPE_SOURCE = "recipes.json"
MAPPING_SOURCE = "ingredient_mapping.json"
NUTRITION_SOURCE = "nutrition_data.json"
DISEASE_RULE_SOURCE = "disease_rules.json"
BIOMARKER_LINK_SOURCE = "biomarker_nutrition_links.json"


# =========================
# Paths
# =========================
BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"

RECIPES_PATH = DATA_DIR / "recipes.json"
INGREDIENT_MAPPING_PATH = DATA_DIR / "ingredient_mapping.json"
NUTRITION_DATA_PATH = DATA_DIR / "nutrition_data.json"
DISEASE_RULES_PATH = DATA_DIR / "disease_rules.json"

BIOMARKER_NUTRITION_LINKS_PATH = DATA_DIR / "biomarker_nutrition_links.json"
BIOMARKER_NUTRIENT_LINKS_PATH = DATA_DIR / "biomarker_nutrient_links.json"


# =========================
# Test recipes
# set() 代表全部匯入
# =========================
TEST_RECIPE_IDS = {
    "r481002",  # 義式千層麵
    "r481005",  # 洋蔥鱸魚豆腐湯
}


# =========================
# 核心營養：主展示圖與疾病推理主要使用
# 注意：這些名稱是解析後的 Nutrition.name
# =========================
CORE_NUTRITION_NAMES = {
    "熱量",
    "修正熱量",
    "蛋白質",
    "脂肪",
    "飽和脂肪",
    "碳水化合物",
    "膳食纖維",
    "糖",
    "鈉",
    "膽固醇",
}


# =========================
# 非營養欄位：不轉成 Nutrition
# =========================
IGNORE_NUTRITION_FIELDS = {
    "整合編號",
    "食品分類",
    "樣品名稱",
    "內容物描述",
    "俗名",
    "廢棄率(%)",
    "P/M/S",
}


# =========================
# 欄位名稱標準化
# key = nutrition_data.json 欄位解析後名稱
# value = Nutrition 節點名稱
# =========================
NUTRITION_NAME_NORMALIZATION = {
    "粗蛋白": "蛋白質",
    "粗脂肪": "脂肪",
    "總碳水化合物": "碳水化合物",
    "糖質總量": "糖",
    "維生素A總量": "維生素A",
    "維生素D總量": "維生素D",
    "維生素E總量": "維生素E",
    "脂肪酸S總量": "飽和脂肪酸總量",
    "脂肪酸M總量": "單元不飽和脂肪酸總量",
    "脂肪酸P總量": "多元不飽和脂肪酸總量",
    "水解胺基酸總量": "胺基酸總量",
}


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


class KGBuilderV72:
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

    @staticmethod
    def parse_nutrition_field(field_name: str) -> Dict[str, str]:
        """
        例：
        熱量(kcal) -> name=熱量, unit=kcal/100g
        粗蛋白(g) -> name=蛋白質, unit=g/100g
        維生素B12(ug) -> name=維生素B12, unit=ug/100g
        P/M/S -> 不會進來，因為被 ignore
        """
        field_name = str(field_name).strip()

        match = re.match(r"^(.*?)\((.*?)\)$", field_name)
        if match:
            raw_name = match.group(1).strip()
            raw_unit = match.group(2).strip()
            unit = f"{raw_unit}/100g" if raw_unit else ""
        else:
            raw_name = field_name
            unit = ""

        nutrition_name = NUTRITION_NAME_NORMALIZATION.get(raw_name, raw_name)

        return {
            "nutrition_name": nutrition_name,
            "unit": unit,
        }

    @staticmethod
    def classify_nutrition(nutrition_name: str, source_field: str) -> str:
        name = nutrition_name
        field = source_field

        if name in {"熱量", "修正熱量", "水分", "灰分", "蛋白質", "脂肪", "碳水化合物", "膳食纖維", "膽固醇"}:
            return "basic"

        if name in {"糖", "葡萄糖", "果糖", "半乳糖", "麥芽糖", "蔗糖", "乳糖"}:
            return "sugar"

        if name in {"鈉", "鉀", "鈣", "鎂", "鐵", "鋅", "磷", "銅", "錳"}:
            return "mineral"

        if name.startswith("維生素") or name in {
            "視網醇當量",
            "視網醇",
            "α-胡蘿蔔素",
            "β-胡蘿蔔素",
            "α-維生素E當量",
            "α-生育酚",
            "β-生育酚",
            "γ-生育酚",
            "δ-生育酚",
            "葉酸",
            "菸鹼素",
        }:
            return "vitamin"

        if "脂肪酸" in name or re.search(r"\(\d+:\d+\)", field) or name in {
            "反式脂肪",
            "飽和脂肪",
            "飽和脂肪酸總量",
            "單元不飽和脂肪酸總量",
            "多元不飽和脂肪酸總量",
            "酪酸",
            "己酸",
            "辛酸",
            "癸酸",
            "月桂酸",
            "肉豆蔻酸",
            "棕櫚酸",
            "硬脂酸",
            "油酸",
            "亞麻油酸",
            "次亞麻油酸",
            "花生油酸",
        }:
            return "fatty_acid"

        if "胺酸" in name or name in {
            "胺基酸總量",
            "天門冬胺酸",
            "酥胺酸",
            "絲胺酸",
            "麩胺酸",
            "脯胺酸",
            "甘胺酸",
            "丙胺酸",
            "胱胺酸",
            "纈胺酸",
            "甲硫胺酸",
            "異白胺酸",
            "白胺酸",
            "酪胺酸",
            "苯丙胺酸",
            "離胺酸",
            "組胺酸",
            "精胺酸",
            "色胺酸",
        }:
            return "amino_acid"

        return "other"

    def extract_all_nutrition_values(self, row: Dict[str, Any]) -> List[Dict[str, Any]]:
        values: List[Dict[str, Any]] = []

        for field_name, raw_value in row.items():
            if field_name in IGNORE_NUTRITION_FIELDS:
                continue

            amount = self.safe_float(raw_value, None)
            if amount is None:
                continue

            parsed = self.parse_nutrition_field(field_name)
            nutrition_name = parsed["nutrition_name"]
            unit = parsed["unit"]
            category = self.classify_nutrition(nutrition_name, field_name)
            is_core = nutrition_name in CORE_NUTRITION_NAMES

            values.append(
                {
                    "nutrition_name": nutrition_name,
                    "amount": amount,
                    "unit": unit,
                    "source_field": field_name,
                    "category": category,
                    "is_core": is_core,
                }
            )

        return values

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
            CREATE INDEX IF NOT EXISTS
            FOR (d:Dish) ON (d.name)
            """,
            """
            CREATE INDEX IF NOT EXISTS
            FOR (i:Ingredient) ON (i.matched_food_name)
            """,
            """
            CREATE INDEX IF NOT EXISTS
            FOR (n:Nutrition) ON (n.category)
            """,
            """
            CREATE INDEX IF NOT EXISTS
            FOR (n:Nutrition) ON (n.is_core)
            """,
        ]

        with self.driver.session() as session:
            for query in queries:
                session.run(query)

        print("Schema ready.")

    # =========================
    # Load recipes
    # =========================
    def load_recipes(self) -> List[Dict[str, Any]]:
        print(f"Loading recipes from: {RECIPES_PATH}")
        recipes = self.load_json_file(RECIPES_PATH, "recipes.json")

        if TEST_RECIPE_IDS:
            selected = [r for r in recipes if r.get("recipe_id") in TEST_RECIPE_IDS]
        else:
            selected = recipes

        print(f"Loaded {len(selected)} recipe(s).")
        for recipe in selected:
            print(f"- {recipe.get('recipe_id')} | {recipe.get('name')}")
        return selected

    # =========================
    # Load ingredient mapping
    # =========================
    def load_ingredient_mapping(self) -> None:
        print(f"Loading ingredient mapping from: {INGREDIENT_MAPPING_PATH}")

        if not INGREDIENT_MAPPING_PATH.exists():
            print("WARNING: ingredient_mapping.json not found. Will use fallback self-mapping.")
            self.mapping_lookup = {}
            return

        raw = self.load_json_file(INGREDIENT_MAPPING_PATH, "ingredient_mapping.json")
        lookup: Dict[str, Dict[str, Any]] = {}

        if isinstance(raw, dict) and all(not isinstance(v, (dict, list)) for v in raw.values()):
            for ingredient_key, food_value in raw.items():
                lookup[self.normalize_key(ingredient_key)] = {
                    "ingredient_name": str(ingredient_key).strip(),
                    "matched_food_name": str(food_value).strip(),
                    "confidence": 1.0,
                    "mapping_source": "ingredient_mapping.json:direct_dict",
                }

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
                    ingredient_name=str(hit["ingredient_name"]).strip(),
                    matched_food_name=str(hit["matched_food_name"]).strip(),
                    confidence=float(hit.get("confidence", 1.0)),
                    mapping_source=str(hit.get("mapping_source", MAPPING_SOURCE)),
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
    # Load nutrition data
    # =========================
    def load_nutrition_data(self) -> None:
        print(f"Loading nutrition data from: {NUTRITION_DATA_PATH}")

        if not NUTRITION_DATA_PATH.exists():
            print("WARNING: nutrition_data.json not found. Nutrition import will be skipped.")
            self.nutrition_by_name = {}
            self.nutrition_by_alias = {}
            return

        raw_data = self.load_json_file(NUTRITION_DATA_PATH, "nutrition_data.json")

        # Handle both list format and dict-of-lists format
        if isinstance(raw_data, dict):
            rows = []
            for category_rows in raw_data.values():
                if isinstance(category_rows, list):
                    rows.extend(category_rows)
                elif isinstance(category_rows, dict):
                    rows.append(category_rows)
        elif isinstance(raw_data, list):
            rows = raw_data
        else:
            print("WARNING: nutrition_data.json format not recognized.")
            rows = []

        by_name: Dict[str, Dict[str, Any]] = {}
        by_alias: Dict[str, Dict[str, Any]] = {}

        for row in rows:
            if not isinstance(row, dict):
                continue

            sample_name = row.get("樣品名稱")
            if sample_name:
                by_name[self.normalize_key(sample_name)] = row

            for alias in self.split_aliases(row.get("俗名")):
                by_alias[self.normalize_key(alias)] = row

        self.nutrition_by_name = by_name
        self.nutrition_by_alias = by_alias

        print(
            f"Loaded nutrition items: {len(rows)} | "
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
    # Load disease / biomarker
    # =========================
    def load_disease_rules(self) -> None:
        print(f"Loading disease rules from: {DISEASE_RULES_PATH}")

        if not DISEASE_RULES_PATH.exists():
            print("WARNING: disease_rules.json not found. Disease rules will be skipped.")
            self.disease_rules = []
            return

        self.disease_rules = self.load_json_file(DISEASE_RULES_PATH, "disease_rules.json")
        print(f"Loaded {len(self.disease_rules)} disease rule seed(s).")

    def load_biomarker_links(self) -> None:
        if BIOMARKER_NUTRITION_LINKS_PATH.exists():
            path = BIOMARKER_NUTRITION_LINKS_PATH
            label = "biomarker_nutrition_links.json"
        elif BIOMARKER_NUTRIENT_LINKS_PATH.exists():
            path = BIOMARKER_NUTRIENT_LINKS_PATH
            label = "biomarker_nutrient_links.json"
        else:
            print("WARNING: biomarker nutrition link JSON not found. Biomarker links will be skipped.")
            self.biomarker_links = []
            return

        print(f"Loading biomarker links from: {path}")
        self.biomarker_links = self.load_json_file(path, label)
        print(f"Loaded {len(self.biomarker_links)} biomarker-nutrition link(s).")

    # =========================
    # Insert Dish and Ingredient
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
            nutrition_match = self.resolve_nutrition_row(mapping.matched_food_name)

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
            d.source = $recipe_source,
            d.builder_version = $version

        WITH d
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
            i.nutrition_source = $nutrition_source,
            i.updated_by_version = $version

        MERGE (d)-[c:CONTAINS]->(i)
        SET c.amount = ing.amount,
            c.unit = ing.unit,
            c.amount_note = ing.amount_note,
            c.name_raw = ing.name_raw,
            c.source = $recipe_source
        """

        with self.driver.session() as session:
            session.run(
                query,
                recipe_id=recipe_id,
                dish_name=dish_name,
                servings=servings,
                ingredients=prepared,
                recipe_source=RECIPE_SOURCE,
                nutrition_source=NUTRITION_SOURCE,
                version=VERSION,
            )

        return prepared

    # =========================
    # Ingredient -> Nutrition
    # =========================
    def upsert_ingredient_nutrition(self, ingredient_name: str, matched_food_name: str) -> None:
        nutrition_match = self.resolve_nutrition_row(matched_food_name)

        if not nutrition_match.matched or not nutrition_match.row:
            print(f"    [nutrition] NOT FOUND for Ingredient={ingredient_name} | matched_food_name={matched_food_name}")
            return

        row = nutrition_match.row
        nutrition_values = self.extract_all_nutrition_values(row)

        if not nutrition_values:
            print(f"    [nutrition] matched but no usable nutrition fields for Ingredient={ingredient_name}")
            return

        query = """
        MATCH (i:Ingredient {name: $ingredient_name})
        UNWIND $nutrition_values AS nv

        MERGE (n:Nutrition {name: nv.nutrition_name})
        ON CREATE SET n.created_by_version = $version

        SET n.category = nv.category,
            n.is_core = nv.is_core,
            n.updated_by_version = $version

        MERGE (i)-[r:HAS_NUTRITION]->(n)
        SET r.amount = nv.amount,
            r.unit = nv.unit,
            r.source_field = nv.source_field,
            r.source = $nutrition_source,
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
                nutrition_source=NUTRITION_SOURCE,
                nutrition_values=nutrition_values,
                version=VERSION,
            )

        core_count = sum(1 for v in nutrition_values if v["is_core"])
        print(
            f"    [nutrition] Ingredient={ingredient_name} "
            f"-> source_food={row.get('樣品名稱')} "
            f"({nutrition_match.matched_by}) | total={len(nutrition_values)} | core={core_count}"
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

            self.upsert_ingredient_nutrition(ingredient_name, matched_food_name)

    # =========================
    # Disease / Biomarker / Nutrition rules
    # =========================
    @staticmethod
    def get_rule_nutrition_name(rule: Dict[str, Any]) -> str:
        name = (
            rule.get("nutrition")
            or rule.get("nutrient")
            or rule.get("name")
            or ""
        )
        return NUTRITION_NAME_NORMALIZATION.get(name, name)

    @staticmethod
    def get_link_nutrition_name(link: Dict[str, Any]) -> str:
        name = (
            link.get("nutrition")
            or link.get("nutrient")
            or link.get("name")
            or ""
        )
        return NUTRITION_NAME_NORMALIZATION.get(name, name)

    def import_disease_biomarker_rules(self) -> None:
        print("\nImporting Disease / Biomarker / Diet Rules ...")

        disease_query = """
        MERGE (d:Disease {name: $disease_name})
        SET d.description = $description,
            d.source = $source,
            d.created_by_version = $version

        WITH d
        UNWIND $biomarkers AS biomarker_name
        MERGE (b:Biomarker {name: biomarker_name})
        ON CREATE SET b.created_by_version = $version

        MERGE (d)-[r:AFFECTS]->(b)
        SET r.source = $source,
            r.version = $version
        """

        rule_query = """
        MERGE (d:Disease {name: $disease_name})
        MERGE (n:Nutrition {name: $nutrition_name})
        ON CREATE SET n.created_by_version = $version

        SET n.is_core = CASE
            WHEN n.name IN $core_names THEN true
            ELSE coalesce(n.is_core, false)
        END

        MERGE (d)-[r:HAS_DIET_RULE]->(n)
        SET r.rule_type = $rule_type,
            r.min_value = $min_value,
            r.max_value = $max_value,
            r.unit = $unit,
            r.label = $label,
            r.note = $note,
            r.version = $version,
            r.source = $source
        """

        biomarker_query = """
        MERGE (b:Biomarker {name: $biomarker_name})
        ON CREATE SET b.created_by_version = $version

        MERGE (n:Nutrition {name: $nutrition_name})
        ON CREATE SET n.created_by_version = $version

        SET n.is_core = CASE
            WHEN n.name IN $core_names THEN true
            ELSE coalesce(n.is_core, false)
        END

        MERGE (n)-[r:AFFECTS_BIOMARKER]->(b)
        SET r.relation = $relation,
            r.effect = $effect,
            r.version = $version,
            r.source = $source
        """

        with self.driver.session() as session:
            for disease in self.disease_rules:
                session.run(
                    disease_query,
                    disease_name=disease.get("disease"),
                    description=disease.get("description"),
                    biomarkers=disease.get("biomarkers", []),
                    source=DISEASE_RULE_SOURCE,
                    version=VERSION,
                )

                for rule in disease.get("rules", []):
                    nutrition_name = self.get_rule_nutrition_name(rule)
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
                        source=DISEASE_RULE_SOURCE,
                        version=VERSION,
                        core_names=list(CORE_NUTRITION_NAMES),
                    )

            for link in self.biomarker_links:
                nutrition_name = self.get_link_nutrition_name(link)
                biomarker_name = link.get("biomarker")

                if not nutrition_name or not biomarker_name:
                    continue

                session.run(
                    biomarker_query,
                    biomarker_name=biomarker_name,
                    nutrition_name=nutrition_name,
                    relation=link.get("relation"),
                    effect=link.get("effect"),
                    source=BIOMARKER_LINK_SOURCE,
                    version=VERSION,
                    core_names=list(CORE_NUTRITION_NAMES),
                )

        print(f"Imported {len(self.disease_rules)} disease seed(s).")
        print(f"Imported {len(self.biomarker_links)} biomarker-nutrition link(s).")

    # =========================
    # Suggested Queries
    # =========================
    def print_suggested_queries(self) -> None:
        print("\nSuggested Neo4j queries:")
        print("-" * 72)
        print(
            """
// 主展示鏈：只查核心 Nutrition
MATCH p =
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[:HAS_NUTRITION]->
(n:Nutrition {is_core: true})
-[:AFFECTS_BIOMARKER]->
(b:Biomarker)
RETURN p
            """.strip()
        )
        print("-" * 72)
        print(
            """
// 完整營養表格：不限制核心營養
MATCH
(d:Dish {name: "義式千層麵"})
-[:CONTAINS]->
(i:Ingredient)
-[r:HAS_NUTRITION]->
(n:Nutrition)
RETURN
  d.name AS dish,
  i.name AS ingredient,
  n.name AS nutrition,
  n.category AS category,
  n.is_core AS is_core,
  r.amount AS amount,
  r.unit AS unit,
  r.source_food_name AS source_food_name,
  r.source_field AS source_field
ORDER BY ingredient, category, nutrition
            """.strip()
        )
        print("-" * 72)
        print(
            """
// 查看某一個 Ingredient 的完整營養
MATCH
(i:Ingredient {name: "牛奶"})
-[r:HAS_NUTRITION]->
(n:Nutrition)
RETURN
  i.name AS ingredient,
  n.name AS nutrition,
  n.category AS category,
  n.is_core AS is_core,
  r.amount AS amount,
  r.unit AS unit,
  r.source_food_name AS source_food_name,
  r.source_field AS source_field
ORDER BY category, nutrition
            """.strip()
        )
        print("-" * 72)

    # =========================
    # Main
    # =========================
    def run(self) -> None:
        self.create_schema()
        self.load_ingredient_mapping()
        self.load_nutrition_data()
        self.load_disease_rules()
        self.load_biomarker_links()

        recipes = self.load_recipes()

        for recipe in recipes:
            print("=" * 72)
            print(f"Processing recipe: {recipe.get('recipe_id')} | {recipe.get('name')}")

            prepared = self.insert_recipe_and_ingredients(recipe)

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
    builder = KGBuilderV72()
    try:
        builder.run()
    finally:
        builder.close()
