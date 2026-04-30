from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Dict, List

from dotenv import dotenv_values
from neo4j import GraphDatabase
from openai import OpenAI


def _load_env_files() -> None:
    env_paths = [
        Path(__file__).resolve().parents[2] / ".env",  # workspace/.env
        Path(__file__).resolve().parent / ".env",  # workspace/src/test1/.env
    ]
    placeholder_values = {"", "dummy-key"}

    for env_path in env_paths:
        if not env_path.exists():
            continue
        values = dotenv_values(env_path)
        for key, value in values.items():
            if value is None:
                continue
            current = os.getenv(key, "")
            if current in placeholder_values:
                os.environ[key] = value


_load_env_files()

NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_API_BASE = os.getenv("OPENAI_API_BASE", "https://api.openai.com/v1")

client = OpenAI(api_key=OPENAI_API_KEY, base_url=OPENAI_API_BASE)


class QueryEngine:
    def __init__(self, uri: str, user: str, password: str) -> None:
        self.driver = GraphDatabase.driver(uri, auth=(user, password))

    def close(self) -> None:
        self.driver.close()

    def get_dish_risk_path(self, dish_name: str, disease_name: str) -> List[Dict[str, Any]]:
        query = """
        MATCH (d:Dish {name: $dish_name})-[c:CONTAINS]->(i:Ingredient)
        OPTIONAL MATCH (i)-[:MAP_TO]->(f:FoodItem)-[hn:HAS_NUTRIENT]->(n:Nutrient)
        OPTIONAL MATCH (n)-[af:AFFECTS]->(b:Biomarker)-[:ASSOCIATED_WITH]->(dis:Disease {name: $disease_name})
        RETURN
          d.name AS dish,
          i.name AS ingredient,
          c.amount AS ingredient_amount,
          c.unit AS ingredient_unit,
          f.name AS food_item,
          n.name AS nutrient,
          hn.amount AS nutrient_amount,
          hn.unit AS nutrient_unit,
          b.name AS biomarker,
          af.effect AS effect,
          dis.name AS disease
        ORDER BY ingredient, nutrient
        """
        with self.driver.session() as session:
            result = session.run(query, dish_name=dish_name, disease_name=disease_name)
            return [record.data() for record in result]

    def summarize_for_llm(self, rows: List[Dict[str, Any]], user_profile: Dict[str, Any]) -> str:
        lines = [
            f"疾病：{user_profile.get('disease', '')}",
            f"限制：{user_profile.get('restrictions', [])}",
            "圖譜路徑：",
        ]
        for r in rows:
            lines.append(
                "- 食材:{ingredient} 食物項:{food_item} 營養素:{nutrient} "
                "含量:{nutrient_amount} {nutrient_unit} 影響:{biomarker}/{effect}".format(
                    ingredient=r.get("ingredient"),
                    food_item=r.get("food_item"),
                    nutrient=r.get("nutrient"),
                    nutrient_amount=r.get("nutrient_amount"),
                    nutrient_unit=r.get("nutrient_unit"),
                    biomarker=r.get("biomarker"),
                    effect=r.get("effect"),
                )
            )
        return "\n".join(lines)

    def generate_recommendation(self, dish_name: str, disease_name: str) -> Dict[str, Any]:
        if not OPENAI_API_KEY or OPENAI_API_KEY.strip() == "dummy-key":
            raise RuntimeError(
                "OPENAI_API_KEY is missing or set to a placeholder (dummy-key). "
                "Set it in the environment, or put the real key in `workspace/.env` "
                "or `workspace/src/test1/.env`."
            )

        rows = self.get_dish_risk_path(dish_name, disease_name)
        if not rows:
            return {
                "dish": dish_name,
                "disease": disease_name,
                "graph_rows": [],
                "advice": "圖譜中找不到此料理與該疾病的關聯路徑，暫時無法提供建議。",
            }

        context = self.summarize_for_llm(
            rows,
            user_profile={"disease": disease_name, "restrictions": []},
        )

        prompt = f"""
你是營養與健康助理。請根據下方「圖譜路徑」給出對使用者的建議，需包含：
1) 風險點（哪些食材/營養素可能增加風險）
2) 可行替代方案或減量建議
3) 一句總結

請用繁體中文、條列且簡潔，不要杜撰沒有出現在圖譜路徑中的數值。

{context}
""".strip()

        response = client.responses.create(
            model="gpt-4.1-nano",
            input=prompt,
            temperature=0.0,
        )

        return {
            "dish": dish_name,
            "disease": disease_name,
            "graph_rows": rows,
            "advice": response.output_text.strip(),
        }


if __name__ == "__main__":
    engine = QueryEngine(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)
    try:
        result = engine.generate_recommendation("蒜香蝦仁義大利麵", "高血壓")
        print(result["advice"])
    finally:
        engine.close()
