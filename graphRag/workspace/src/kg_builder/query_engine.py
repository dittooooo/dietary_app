# - 讀取 `.env` 裡的 Neo4j / OpenAI 設定。
# - 把使用者問題轉成 Cypher。
# - 檢查 Cypher 是否安全。
# - 執行 Neo4j 查詢。
# - 把查詢結果交給模型整理成回答。

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

from neo4j import GraphDatabase
from neo4j.exceptions import CypherSyntaxError
from neo4j.graph import Node, Path as Neo4jPath, Relationship

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


def _load_env_files() -> None:
    env_paths = [
        Path(__file__).resolve().parents[2] / ".env",  # graphRag/workspace/.env
        Path(__file__).resolve().parent / ".env",  # graphRag/workspace/src/kg_builder/.env
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
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")


GRAPH_SCHEMA = """
Neo4j graph schema for the dietary GraphRAG system:

Nodes:
- (:Dish {recipe_id, name, servings, source, builder_version})
- (:Ingredient {name, matched_food_name, matched_food_id, matched_sample_name,
  matched_category, mapping_confidence, nutrition_matched, mapping_method})
- (:FoodItem {food_id, name, category, description, aliases})
- (:Nutrition {nutrition_id, name, name_zh, name_en, unit, category, source_column})
- (:Biomarker {name})
- (:Disease {disease_id, name, name_en, diet_pattern, risk_notes})

Relationships:
- (:Dish)-[:CONTAINS {amount, unit, amount_note, name_raw, source}]->(:Ingredient)
- (:Ingredient)-[:MAPS_TO {method, source}]->(:FoodItem)
- (:FoodItem)-[:HAS_NUTRITION {amount_per_100g, amount, unit, source_column}]->(:Nutrition)
- (:Ingredient)-[:HAS_NUTRITION {amount_per_100g, amount_per_serving, amount, unit,
  source_column, source_food_id, source_food_name}]->(:Nutrition)
- (:Nutrition)-[:AFFECTS_BIOMARKER {relation, effect}]->(:Biomarker)
- (:Disease)-[:AFFECTS {source, version}]->(:Biomarker)
- (:Disease)-[:HAS_DIET_RULE {relation, rule_type, direction, target_note, note,
  food_level_condition, food_level, food_level_note, criteria_json,
  food_level_rule_json, example_foods_json, reason, sources_json}]->(:Nutrition)

Common reasoning paths:
- Dish -> Ingredient -> Nutrition -> Disease diet rules
- Dish -> Ingredient -> FoodItem -> Nutrition -> Disease diet rules
- Disease -> HAS_DIET_RULE -> Nutrition <- HAS_NUTRITION <- Ingredient <- CONTAINS <- Dish
""".strip()


TEXT_TO_CYPHER_SYSTEM_PROMPT = f"""
You are a Text-to-Cypher translator for a Neo4j dietary knowledge graph.
Create exactly one read-only Cypher query for the user's Traditional Chinese question.

{GRAPH_SCHEMA}

Rules:
- Return JSON only: {{"cypher": "...", "rationale": "..."}}
- Use only MATCH, OPTIONAL MATCH, WITH, WHERE, RETURN, ORDER BY, LIMIT.
- Do not use CREATE, MERGE, SET, DELETE, DETACH, REMOVE, DROP, LOAD CSV, CALL, APOC, or procedures.
- Return scalar columns with clear aliases. Do not return raw path objects only.
- Prefer CONTAINS matching for Chinese names, for example: dish.name CONTAINS "義式千層麵".
- For dish and disease risk questions, retrieve ingredients, mapped food items,
  nutrition amounts, disease diet rules, relation/direction/reason, and rule notes.
- When using HAS_DIET_RULE, always bind the relationship variable:
  (dis:Disease)-[rule:HAS_DIET_RULE]->(n:Nutrition)
  Return rule properties such as rule.relation, rule.direction, rule.note, rule.reason.
- Never write invalid expressions such as "dis HAS_DIET_RULE AS diet_rules".
- Biomarker paths may be absent in the official imported dataset; use disease diet rules
  as the main evidence when biomarker paths are not present.
- Always add LIMIT 50 unless a smaller limit is clearly better.
- Do not invent labels, relationships, or properties outside the schema.

Good example:
MATCH (d:Dish)-[c:CONTAINS]->(ing:Ingredient)-[:MAPS_TO]->(f:FoodItem)
MATCH (ing)-[hn:HAS_NUTRITION]->(n:Nutrition)<-[rule:HAS_DIET_RULE]-(dis:Disease)
WHERE d.name CONTAINS "義式千層麵" AND dis.name CONTAINS "高血壓"
RETURN d.name AS dish_name, ing.name AS ingredient_name, f.name AS food_item_name,
       n.name AS nutrition_name, hn.amount_per_serving AS amount_per_serving,
       hn.unit AS nutrition_unit, dis.name AS disease_name,
       rule.relation AS diet_rule_relation, rule.direction AS diet_rule_direction,
       rule.note AS diet_rule_note, rule.reason AS diet_rule_reason
LIMIT 50
""".strip()


ANSWER_SYSTEM_PROMPT = """
你是飲食建議多代理人系統中的「營養代理人」。
你會根據 Neo4j 知識圖譜查詢結果回答，而不是憑空猜測。

回答規則：
- 使用繁體中文。
- 第一句先給結論，直接回答使用者問題，結論不要超過 40 個字。
- 說明料理、食材、營養素、生理指標或疾病規則之間的多跳關係。
- 若資料不足，明確說明缺少哪一段圖譜證據。
- 不要把結果包裝成醫療診斷；最後提醒仍需依個人病況與醫囑調整。
""".strip()


WRITE_KEYWORDS = re.compile(
    r"\b(CREATE|MERGE|SET|DELETE|DETACH|REMOVE|DROP|LOAD\s+CSV|CALL|APOC|"
    r"CREATE\s+INDEX|CREATE\s+CONSTRAINT|ALTER|GRANT|DENY|REVOKE|START)\b",
    re.IGNORECASE,
)


class QueryEngine:
    def __init__(
        self,
        uri: str,
        user: str,
        password: str,
        *,
        openai_api_key: str = OPENAI_API_KEY,
        openai_api_base: str = OPENAI_API_BASE,
        model: str = OPENAI_MODEL,
    ) -> None:
        self.driver = GraphDatabase.driver(uri, auth=(user, password))
        self.openai_api_key = openai_api_key
        self.openai_api_base = openai_api_base
        self.model = model
        self._client: Optional[Any] = None

    def close(self) -> None:
        self.driver.close()

    @property
    def client(self) -> Any:
        if not self.openai_api_key or self.openai_api_key.strip() == "dummy-key":
            raise RuntimeError(
                "OPENAI_API_KEY is missing or set to dummy-key. Set it in the "
                "environment, graphRag/workspace/.env, or "
                "graphRag/workspace/src/kg_builder/.env."
            )
        if self._client is None:
            from openai import OpenAI

            self._client = OpenAI(api_key=self.openai_api_key, base_url=self.openai_api_base)
        return self._client

    def generate_cypher(self, question: str) -> Dict[str, str]:
        output_text = self._complete(
            [
                {"role": "system", "content": TEXT_TO_CYPHER_SYSTEM_PROMPT},
                {"role": "user", "content": question},
            ]
        )
        payload = self._parse_json_object(output_text)
        cypher = self._clean_cypher(str(payload.get("cypher", "")))
        self.validate_read_only_cypher(cypher)
        return {
            "cypher": cypher,
            "rationale": str(payload.get("rationale", "")).strip(),
        }

    def execute_cypher(self, cypher: str) -> List[Dict[str, Any]]:
        self.validate_read_only_cypher(cypher)
        with self.driver.session() as session:
            result = session.run(cypher)
            return [{key: self._to_plain_value(value) for key, value in record.data().items()} for record in result]

    def ask(self, question: str) -> Dict[str, Any]:
        cypher_payload = self.generate_dish_disease_cypher(question) or self.generate_cypher(question)
        cypher = cypher_payload["cypher"]
        try:
            rows = self.execute_cypher(cypher)
        except CypherSyntaxError as exc:
            cypher = self.repair_cypher(question, cypher, str(exc))
            rows = self.execute_cypher(cypher)

        answer = self.generate_answer(question, cypher, rows)
        return {
            "question": question,
            "cypher": cypher,
            "cypher_rationale": cypher_payload["rationale"],
            "graph_rows": rows,
            "answer": answer,
        }

    def generate_dish_disease_cypher(self, question: str) -> Optional[Dict[str, str]]:
        dish_name = self.find_mentioned_node_name("Dish", question)
        disease_name = self.find_mentioned_node_name("Disease", question)
        if not dish_name or not disease_name:
            return None

        dish_literal = json.dumps(dish_name, ensure_ascii=False)
        disease_literal = json.dumps(disease_name, ensure_ascii=False)
        cypher = f"""
        MATCH (d:Dish {{name: {dish_literal}}})-[c:CONTAINS]->(ing:Ingredient)
        MATCH (ing)-[hn:HAS_NUTRITION]->(n:Nutrition)<-[rule:HAS_DIET_RULE]-(dis:Disease {{name: {disease_literal}}})
        OPTIONAL MATCH (f:FoodItem {{food_id: hn.source_food_id}})
        WHERE c.matched_food_id IS NULL OR hn.source_food_id = c.matched_food_id
        RETURN
          d.name AS dish_name,
          ing.name AS ingredient_name,
          coalesce(f.name, hn.source_food_name) AS food_item_name,
          n.name AS nutrition_name,
          n.name_zh AS nutrition_name_zh,
          n.category AS nutrition_category,
          hn.amount_per_serving AS amount_per_serving,
          hn.amount_per_100g AS amount_per_100g,
          hn.unit AS nutrition_unit,
          dis.name AS disease_name,
          rule.relation AS diet_rule_relation,
          rule.direction AS diet_rule_direction,
          rule.note AS diet_rule_note,
          rule.reason AS diet_rule_reason,
          rule.food_level_condition AS food_level_condition,
          rule.sources_json AS sources_json
        ORDER BY diet_rule_relation, ingredient_name, nutrition_name
        LIMIT 50
        """.strip()
        return {
            "cypher": cypher,
            "rationale": "Detected a dish and disease in the question; used the stable dish-disease GraphRAG query.",
        }

    def find_mentioned_node_name(self, label: str, question: str) -> Optional[str]:
        if label not in {"Dish", "Disease"}:
            raise ValueError(f"Unsupported label for mention lookup: {label}")
        query = f"""
        MATCH (n:{label})
        WHERE $question CONTAINS n.name
        RETURN n.name AS name
        ORDER BY size(n.name) DESC
        LIMIT 1
        """
        with self.driver.session() as session:
            record = session.run(query, question=question).single()
            return record["name"] if record else None

    def generate_answer(self, question: str, cypher: str, rows: List[Dict[str, Any]]) -> str:
        context = {
            "question": question,
            "cypher": cypher,
            "row_count": len(rows),
            "rows": rows[:50],
        }
        return self._complete(
            [
                {"role": "system", "content": ANSWER_SYSTEM_PROMPT},
                {"role": "user", "content": json.dumps(context, ensure_ascii=False, indent=2)},
            ]
        ).strip()

    def repair_cypher(self, question: str, cypher: str, error: str) -> str:
        prompt = {
            "question": question,
            "bad_cypher": cypher,
            "neo4j_error": error,
            "schema": GRAPH_SCHEMA,
            "instructions": (
                "Repair the Cypher. Return JSON only with keys cypher and rationale. "
                "Keep it read-only. For HAS_DIET_RULE use [rule:HAS_DIET_RULE] and "
                "return rule properties, never a bare relationship type expression."
            ),
        }
        output_text = self._complete(
            [
                {"role": "system", "content": TEXT_TO_CYPHER_SYSTEM_PROMPT},
                {"role": "user", "content": json.dumps(prompt, ensure_ascii=False, indent=2)},
            ]
        )
        payload = self._parse_json_object(output_text)
        repaired = self._clean_cypher(str(payload.get("cypher", "")))
        self.validate_read_only_cypher(repaired)
        return repaired

    def generate_recommendation(self, dish_name: str, disease_name: str) -> Dict[str, Any]:
        question = f"{dish_name} 對 {disease_name} 患者有什麼飲食風險與建議？"
        result = self.ask(question)
        return {
            "dish": dish_name,
            "disease": disease_name,
            "question": question,
            "cypher": result["cypher"],
            "graph_rows": result["graph_rows"],
            "advice": result["answer"],
        }

    @staticmethod
    def validate_read_only_cypher(cypher: str) -> None:
        if not cypher.strip():
            raise ValueError("Generated Cypher is empty.")
        if ";" in cypher.strip().rstrip(";"):
            raise ValueError("Generated Cypher contains multiple statements.")
        if WRITE_KEYWORDS.search(cypher):
            raise ValueError(f"Generated Cypher is not read-only:\n{cypher}")
        if not re.match(r"^\s*(MATCH|OPTIONAL\s+MATCH)\b", cypher, re.IGNORECASE):
            raise ValueError("Generated Cypher must start with MATCH or OPTIONAL MATCH.")
        if not re.search(r"\bRETURN\b", cypher, re.IGNORECASE):
            raise ValueError("Generated Cypher must contain RETURN.")

    def _complete(self, messages: List[Dict[str, str]]) -> str:
        response = self.client.chat.completions.create(
            model=self.model,
            messages=messages,
            temperature=0.0,
        )
        content = response.choices[0].message.content
        if not content:
            raise RuntimeError("LLM returned an empty response.")
        return content

    @staticmethod
    def _parse_json_object(text: str) -> Dict[str, Any]:
        cleaned = text.strip()
        if cleaned.startswith("```"):
            cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned, flags=re.IGNORECASE)
            cleaned = re.sub(r"\s*```$", "", cleaned)
        try:
            payload = json.loads(cleaned)
        except json.JSONDecodeError as exc:
            raise ValueError(f"LLM did not return valid JSON: {text}") from exc
        if not isinstance(payload, dict):
            raise ValueError(f"LLM JSON response must be an object: {text}")
        return payload

    @staticmethod
    def _clean_cypher(cypher: str) -> str:
        cleaned = cypher.strip()
        if cleaned.startswith("```"):
            cleaned = re.sub(r"^```(?:cypher)?\s*", "", cleaned, flags=re.IGNORECASE)
            cleaned = re.sub(r"\s*```$", "", cleaned)
        return cleaned.strip().rstrip(";").strip()

    @classmethod
    def _to_plain_value(cls, value: Any) -> Any:
        if isinstance(value, Node):
            return {
                "labels": sorted(value.labels),
                "properties": dict(value.items()),
            }
        if isinstance(value, Relationship):
            return {
                "type": value.type,
                "properties": dict(value.items()),
            }
        if isinstance(value, Neo4jPath):
            return {
                "nodes": [cls._to_plain_value(node) for node in value.nodes],
                "relationships": [cls._to_plain_value(rel) for rel in value.relationships],
            }
        if isinstance(value, list):
            return [cls._to_plain_value(item) for item in value]
        if isinstance(value, dict):
            return {key: cls._to_plain_value(item) for key, item in value.items()}
        return value


def main() -> None:
    parser = argparse.ArgumentParser(description="Text-to-Cypher GraphRAG nutrition agent")
    parser.add_argument("question", nargs="?", default="義式千層麵對高血壓患者有什麼影響？")
    parser.add_argument("--show-cypher", action="store_true")
    args = parser.parse_args()

    engine = QueryEngine(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)
    try:
        result = engine.ask(args.question)
        if args.show_cypher:
            print(result["cypher"])
            print()
        print(result["answer"])
    finally:
        engine.close()


if __name__ == "__main__":
    main()
