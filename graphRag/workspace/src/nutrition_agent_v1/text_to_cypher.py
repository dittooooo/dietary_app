from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional

from .config import (
    GRAPH_SCHEMA,
    NEO4J_PASSWORD,
    NEO4J_URI,
    NEO4J_USER,
    OPENAI_API_BASE,
    OPENAI_API_KEY,
    OPENAI_MODEL,
)
from .cypher_guard import validate_read_only_cypher
from .models import HealthCondition, QuestionType


LANGCHAIN_TEXT_TO_CYPHER_TEMPLATE = """
你是營養知識圖譜的 Text-to-Cypher 前置模組。
目前只處理兩種問題：
1. 單一道料理適合度判斷
2. 多道料理比較

Neo4j schema:
{schema}

請只輸出 Cypher，不要輸出解釋、Markdown 或 JSON。
限制：
- 只產生唯讀 Cypher。
- 使用 MATCH / OPTIONAL MATCH / WHERE / RETURN / ORDER BY / LIMIT。
- 不要 CREATE、MERGE、SET、DELETE、CALL、APOC。
- HAS_DIET_RULE 關係必須命名為 rule，例如 [rule:HAS_DIET_RULE]。
- 查詢應回傳料理、食材、營養素每份含量、疾病規則與理由。
- 慢性疾病只根據使用者健康條件 JSON 的 chronic_diseases，不要從問題文字推測或抽取疾病。
- 如果使用者健康條件有 chronic_diseases，請把那些疾病納入 WHERE 條件。
- 如果是比較題，WHERE 需包含多個料理名稱。

使用者問題與健康條件：
{question}
""".strip()


class TextToCypherTranslator:
    """Temporary pre-processing module.

    The production plan is to move Text-to-Cypher outside nutrition_agent and pass
    `cypher` directly into the GraphRAG retriever. This adapter uses LangChain so
    it can be removed cleanly later.
    """

    def __init__(
        self,
        driver: Any,
        *,
        openai_api_key: str = OPENAI_API_KEY,
        openai_api_base: str = OPENAI_API_BASE,
        model: str = OPENAI_MODEL,
    ) -> None:
        self.driver = driver
        self.openai_api_key = openai_api_key
        self.openai_api_base = openai_api_base
        self.model = model
        self._schema: Optional[str] = None

    def translate(
        self,
        question: str,
        health_condition: HealthCondition,
        question_type: Optional[QuestionType] = None,
    ) -> Dict[str, str]:
        inferred_type = infer_question_type(question)
        effective_question_type = inferred_type if inferred_type == "dish_comparison" else question_type or inferred_type
        dish_targets = self.resolve_dish_targets(question, effective_question_type)
        disease_names = self.resolve_diseases(health_condition)

        if dish_targets:
            detected_type = "dish_comparison" if len(dish_targets) >= 2 else effective_question_type
            cypher = build_dish_rule_cypher(dish_targets, disease_names)
            return {
                "cypher": cypher,
                "question_type": detected_type,
                "rationale": "Detected dish names from Neo4j and used chronic diseases from user profile only.",
            }

        return self.translate_with_langchain(question, health_condition, effective_question_type)

    def find_mentioned_dishes(
        self,
        question: str,
        question_type: Optional[QuestionType] = None,
        limit: int = 8,
    ) -> List[str]:
        return [target["display_name"] for target in self.resolve_dish_targets(question, question_type, limit)]

    def resolve_dish_targets(
        self,
        question: str,
        question_type: Optional[QuestionType] = None,
        limit: int = 8,
    ) -> List[Dict[str, str]]:
        candidates = extract_dish_candidates(question) if question_type == "dish_comparison" else []
        if candidates:
            candidate_targets = self.find_dish_targets_by_candidates(candidates, limit=limit)
            if len(candidate_targets) >= 2:
                return candidate_targets

        query = """
        MATCH (d:Dish)
        WHERE $question CONTAINS d.name
        RETURN d.name AS name
        ORDER BY size(d.name) DESC
        LIMIT $limit
        """
        with self.driver.session() as session:
            direct_matches = [row["name"] for row in session.run(query, question=question, limit=limit)]

        if candidates:
            candidate_targets = self.find_dish_targets_by_candidates(candidates, limit=limit)
            if candidate_targets:
                return candidate_targets

        return [
            {"display_name": name, "match_name": name}
            for name in prune_generic_dish_names(direct_matches)
        ]

    def find_dish_targets_by_candidates(self, candidates: List[str], limit: int = 8) -> List[Dict[str, str]]:
        query = """
        UNWIND $candidates AS candidate
        MATCH (d:Dish)
        WHERE d.name = candidate
           OR d.name CONTAINS candidate
           OR candidate CONTAINS d.name
        WITH d.name AS name, candidate,
             CASE
               WHEN d.name = candidate THEN 100
               WHEN d.name CONTAINS candidate THEN 80 + size(candidate)
               WHEN candidate CONTAINS d.name THEN 20 + size(d.name)
               ELSE 0
             END AS score
        ORDER BY candidate, score DESC, size(name) DESC
        WITH candidate, collect(name)[0] AS best_name, collect(score)[0] AS best_score
        WHERE best_name IS NOT NULL AND best_score >= 20
        RETURN candidate, best_name AS name
        ORDER BY size(name) DESC
        LIMIT $limit
        """
        with self.driver.session() as session:
            rows = [dict(row) for row in session.run(query, candidates=candidates, limit=limit)]

        targets: List[Dict[str, str]] = []
        for row in rows:
            candidate = row["candidate"]
            match_name = row["name"]
            if not candidate or not match_name:
                continue
            target = {"display_name": candidate, "match_name": match_name}
            if target not in targets:
                targets.append(target)
        return targets

    def resolve_diseases(self, health_condition: HealthCondition) -> List[str]:
        if health_condition.has_chronic_disease and health_condition.chronic_diseases:
            return health_condition.chronic_diseases
        return []

    def translate_with_langchain(
        self,
        question: str,
        health_condition: HealthCondition,
        question_type: Optional[QuestionType],
    ) -> Dict[str, str]:
        if not self.openai_api_key or self.openai_api_key.strip() == "dummy-key":
            raise RuntimeError("Cannot run LangChain Text-to-Cypher: OPENAI_API_KEY is missing.")

        try:
            from langchain_community.chains.graph_qa.cypher import GraphCypherQAChain, extract_cypher
            from langchain_core.prompts import PromptTemplate
            from langchain_openai import ChatOpenAI
        except ModuleNotFoundError as exc:
            raise RuntimeError(
                "LangChain Text-to-Cypher dependencies are missing. Install "
                "`langchain`, `langchain-community`, and `langchain-openai` in the container."
            ) from exc

        llm = self._create_langchain_llm(ChatOpenAI)
        graph = self._create_langchain_graph()
        cypher_prompt = PromptTemplate.from_template(LANGCHAIN_TEXT_TO_CYPHER_TEMPLATE)
        chain = GraphCypherQAChain.from_llm(
            llm=llm,
            graph=graph,
            cypher_prompt=cypher_prompt,
            validate_cypher=True,
            allow_dangerous_requests=True,
        )
        enriched_question = self._build_langchain_question(question, health_condition, question_type)
        content = chain.cypher_generation_chain.run(
            {"question": enriched_question, "schema": chain.graph_schema}
        )
        cypher = extract_cypher(content).strip()
        validate_read_only_cypher(cypher)
        return {
            "cypher": cypher,
            "question_type": question_type or infer_question_type(question),
            "rationale": "Generated by LangChain GraphCypherQAChain cypher_generation_chain.",
        }

    def langchain_schema(self) -> str:
        if self._schema is not None:
            return self._schema

        try:
            try:
                from langchain_community.graphs import Neo4jGraph
            except ModuleNotFoundError:
                from langchain_neo4j import Neo4jGraph

            graph = Neo4jGraph(
                url=NEO4J_URI,
                username=NEO4J_USER,
                password=NEO4J_PASSWORD,
            )
            schema = getattr(graph, "schema", None) or getattr(graph, "get_schema", None)
            self._schema = schema() if callable(schema) else str(schema)
        except Exception:
            self._schema = GRAPH_SCHEMA

        return self._schema

    def _create_langchain_llm(self, chat_openai_cls: Any) -> Any:
        kwargs = {
            "model": self.model,
            "temperature": 0.0,
            "api_key": self.openai_api_key,
            "base_url": self.openai_api_base,
        }
        try:
            return chat_openai_cls(**kwargs)
        except TypeError:
            return chat_openai_cls(
                model_name=self.model,
                temperature=0.0,
                openai_api_key=self.openai_api_key,
                openai_api_base=self.openai_api_base,
            )

    def _create_langchain_graph(self) -> Any:
        try:
            from langchain_community.graphs.graph_store import GraphStore
        except ModuleNotFoundError:
            from langchain_core.graph_vectorstores import GraphStore

        class NutritionGraphStore(GraphStore):
            @property
            def get_schema(inner_self) -> str:
                return GRAPH_SCHEMA

            @property
            def get_structured_schema(inner_self) -> Dict[str, Any]:
                return nutrition_structured_schema()

            @property
            def structured_schema(inner_self) -> Dict[str, Any]:
                return nutrition_structured_schema()

            def query(
                inner_self,
                query: str,
                params: Optional[Dict[str, Any]] = None,
            ) -> List[Dict[str, Any]]:
                validate_read_only_cypher(query)
                with self.driver.session() as session:
                    return [dict(record) for record in session.run(query, params or {})]

            def refresh_schema(inner_self) -> None:
                return None

            def add_graph_documents(inner_self, graph_documents: List[Any], include_source: bool = False) -> None:
                raise NotImplementedError("NutritionGraphStore is read-only.")

        return NutritionGraphStore()

    @staticmethod
    def _build_langchain_question(
        question: str,
        health_condition: HealthCondition,
        question_type: Optional[QuestionType],
    ) -> str:
        return "\n".join(
            [
                f"問題：{question}",
                f"問題類型提示：{question_type or 'unknown'}",
                "疾病判斷限制：不要從問題文字抽取慢性病，只能使用下方健康條件 JSON。",
                "使用者健康條件："
                + json.dumps(health_condition.model_dump(), ensure_ascii=False),
            ]
        )


def build_dish_rule_cypher(dish_targets: List[Dict[str, str]], disease_names: List[str]) -> str:
    targets_cypher = cypher_target_list(dish_targets)
    if disease_names:
        diseases_json = json.dumps(disease_names, ensure_ascii=False)
        disease_match = f"""
    OPTIONAL MATCH (dis:Disease)-[rule:HAS_DIET_RULE]->(n)
    WHERE dis.name IN {diseases_json}
        """.rstrip()
    else:
        disease_match = """
    WITH d, c, ing, hn, n, null AS dis, null AS rule
        """.rstrip()

    return f"""
    UNWIND {targets_cypher} AS dish_target
    MATCH (d:Dish)-[c:CONTAINS]->(ing:Ingredient)
    WHERE d.name = dish_target.match_name
    MATCH (ing)-[hn:HAS_NUTRITION]->(n:Nutrition)
{disease_match}
    OPTIONAL MATCH (f:FoodItem {{food_id: hn.source_food_id}})
    WHERE c.matched_food_id IS NULL OR hn.source_food_id = c.matched_food_id
    RETURN
      dish_target.display_name AS dish_name,
      d.name AS matched_dish_name,
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
    ORDER BY diet_rule_relation, ingredient_name, nutrition_name, dish_name
    LIMIT 1000
    """.strip()


def cypher_target_list(dish_targets: List[Dict[str, str]]) -> str:
    items = []
    for target in dish_targets:
        display_name = json.dumps(target["display_name"], ensure_ascii=False)
        match_name = json.dumps(target["match_name"], ensure_ascii=False)
        items.append(f"{{display_name: {display_name}, match_name: {match_name}}}")
    return "[" + ", ".join(items) + "]"


def infer_question_type(question: str) -> QuestionType:
    comparison_markers = ("還是", "比較", "哪個", "哪一道", "或是", "vs", "VS")
    if any(marker in question for marker in comparison_markers):
        return "dish_comparison"
    return "single_dish"


def extract_dish_candidates(question: str) -> List[str]:
    cleaned = question
    for token in ("你覺得", "我今天要吃", "今天要吃", "我要吃", "我想吃", "請問", "嗎", "？", "?"):
        cleaned = cleaned.replace(token, " ")
    parts = re.split(r"還是|或是|或者|跟|和|、|,|，|/| vs | VS | v.s. ", cleaned)
    candidates: List[str] = []
    for part in parts:
        candidate = re.sub(r"\s+", "", part)
        candidate = candidate.strip("。.!！")
        if len(candidate) >= 2 and candidate not in candidates:
            candidates.append(candidate)
    return candidates


def prune_generic_dish_names(names: List[str]) -> List[str]:
    deduped: List[str] = []
    for name in names:
        if name and name not in deduped:
            deduped.append(name)

    pruned: List[str] = []
    for name in deduped:
        is_generic = any(other != name and name in other for other in deduped)
        if not is_generic:
            pruned.append(name)
    return pruned


def nutrition_structured_schema() -> Dict[str, Any]:
    return {
        "node_props": {
            "Dish": [
                {"property": "name", "type": "STRING"},
                {"property": "recipe_id", "type": "STRING"},
                {"property": "servings", "type": "INTEGER"},
            ],
            "Ingredient": [
                {"property": "name", "type": "STRING"},
                {"property": "amount", "type": "FLOAT"},
                {"property": "unit", "type": "STRING"},
                {"property": "matched_food_id", "type": "STRING"},
            ],
            "FoodItem": [
                {"property": "food_id", "type": "STRING"},
                {"property": "name", "type": "STRING"},
                {"property": "category", "type": "STRING"},
            ],
            "Nutrition": [
                {"property": "name", "type": "STRING"},
                {"property": "name_zh", "type": "STRING"},
                {"property": "category", "type": "STRING"},
                {"property": "unit", "type": "STRING"},
            ],
            "Disease": [
                {"property": "name", "type": "STRING"},
                {"property": "name_en", "type": "STRING"},
            ],
        },
        "rel_props": {
            "CONTAINS": [
                {"property": "matched_food_id", "type": "STRING"},
                {"property": "amount", "type": "FLOAT"},
                {"property": "unit", "type": "STRING"},
            ],
            "HAS_NUTRITION": [
                {"property": "amount_per_serving", "type": "FLOAT"},
                {"property": "amount_per_100g", "type": "FLOAT"},
                {"property": "unit", "type": "STRING"},
                {"property": "source_food_id", "type": "STRING"},
                {"property": "source_food_name", "type": "STRING"},
            ],
            "MAPS_TO": [
                {"property": "confidence", "type": "FLOAT"},
            ],
            "HAS_DIET_RULE": [
                {"property": "relation", "type": "STRING"},
                {"property": "direction", "type": "STRING"},
                {"property": "note", "type": "STRING"},
                {"property": "reason", "type": "STRING"},
                {"property": "food_level_condition", "type": "STRING"},
                {"property": "sources_json", "type": "STRING"},
            ],
        },
        "relationships": [
            {"start": "Dish", "type": "CONTAINS", "end": "Ingredient"},
            {"start": "Ingredient", "type": "MAPS_TO", "end": "FoodItem"},
            {"start": "Ingredient", "type": "HAS_NUTRITION", "end": "Nutrition"},
            {"start": "Disease", "type": "HAS_DIET_RULE", "end": "Nutrition"},
        ],
    }
