"""
kg_builder.py - V3
功能：
1. 自動建立 Neo4j schema
2. 從 recipes.json 匯入資料
3. 支援只測試 1~2 筆 recipe
4. 建立 Dish / Ingredient / CONTAINS 關係
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import List, Dict

from neo4j import GraphDatabase

# =========================
# 環境設定
# =========================
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")

# =========================
# 路徑設定
# =========================
BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"

RECIPES_PATH = DATA_DIR / "recipes.json"

# =========================
# 測試用（只跑幾筆）
# =========================
TEST_RECIPE_IDS = {
    "r481005",  # 洋蔥鱸魚豆腐湯
    "r481002",  # 義式千層麵
}


# =========================
# Neo4j Builder
# =========================
class KGBuilder:
    def __init__(self):
        print("Connecting to Neo4j...")
        self.driver = GraphDatabase.driver(
            NEO4J_URI,
            auth=(NEO4J_USER, NEO4J_PASSWORD),
        )

    def close(self):
        self.driver.close()

    # =========================
    # 建立 Schema
    # =========================
    def create_schema(self):
        print("Creating schema...")

        queries = [
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (d:Dish) REQUIRE d.name IS UNIQUE
            """,
            """
            CREATE CONSTRAINT IF NOT EXISTS
            FOR (i:Ingredient) REQUIRE i.name IS UNIQUE
            """,
        ]

        with self.driver.session() as session:
            for q in queries:
                session.run(q)

        print("Schema ready.")

    # =========================
    # 讀取 recipes.json
    # =========================
    def load_test_recipes(self) -> List[Dict]:
        print("Loading recipes...")

        with open(RECIPES_PATH, "r", encoding="utf-8") as f:
            recipes = json.load(f)

        selected = [
            r for r in recipes if r["recipe_id"] in TEST_RECIPE_IDS
        ]

        print(f"Loaded {len(selected)} recipes:")
        for r in selected:
            print(f"- {r['recipe_id']} | {r['name']}")

        return selected

    # =========================
    # 寫入 Neo4j
    # =========================
    def insert_recipe(self, recipe: Dict):
        dish_name = recipe["name"]

        query = """
        MERGE (d:Dish {name: $dish_name})
        WITH d
        UNWIND $ingredients AS ing
        MERGE (i:Ingredient {name: ing.name})
        MERGE (d)-[r:CONTAINS]->(i)
        SET r.amount = ing.amount,
            r.unit = ing.unit
        """

        ingredients = []
        for ing in recipe.get("ingredients", []):
            ingredients.append(
                {
                    "name": ing.get("name"),
                    "amount": ing.get("amount_value"),
                    "unit": ing.get("amount_unit"),
                }
            )

        with self.driver.session() as session:
            session.run(
                query,
                dish_name=dish_name,
                ingredients=ingredients,
            )

    # =========================
    # 主流程
    # =========================
    def run(self):
        self.create_schema()

        recipes = self.load_test_recipes()

        for recipe in recipes:
            print("=" * 60)
            print(f"Processing: {recipe['name']}")

            for ing in recipe.get("ingredients", []):
                print(
                    f"  - {ing.get('name')} | "
                    f"{ing.get('amount_value')} {ing.get('amount_unit')}"
                )

            self.insert_recipe(recipe)

        print("\nAll recipes inserted.")


# =========================
# 執行
# =========================
if __name__ == "__main__":
    builder = KGBuilder()
    builder.run()
    builder.close()