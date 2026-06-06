from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional

from .config import GRAPH_QUERY_LIMIT, GRAPH_SCHEMA
from .cypher_guard import validate_read_only_cypher
from .models import DietRecord, HealthCondition, QuestionType, UserProfile


LANGCHAIN_TEXT_TO_CYPHER_TEMPLATE = """
You are a Neo4j Text-to-Cypher generator for a Nutrition GraphRAG system.
Generate exactly one read-only Cypher query. Output Cypher only.

Graph schema:
{schema}

Rules:
1. Use the full JSON payload, not only the question.
2. Use dish_match_results as the source of retrieval targets.
3. If retrieval_strategy is dish_match, query Dish by matched_dish_name.
4. If retrieval_strategy is ingredient_fallback, query Ingredient/FoodItem by input_name.
5. Use health_condition.chronic_diseases as disease_names. Do not infer diseases from question text.
6. Return nutrition rows with dish_name, matched_dish_name, retrieval_strategy, ingredient_name,
   food_item_name, nutrition_name, nutrition_name_zh, nutrition_category, amount_per_serving,
   amount_per_100g, nutrition_unit, disease rule fields.
7. Only use MATCH, OPTIONAL MATCH, WHERE, WITH, UNWIND, RETURN, ORDER BY, LIMIT.
8. Do not use CREATE, MERGE, SET, DELETE, CALL, APOC, LOAD CSV, DROP, REMOVE.
9. Always LIMIT results.

Input JSON:
{payload_json}
""".strip()


class TextToCypherTranslator:
    def __init__(self, driver: Any) -> None:
        self.driver = driver

    def translate(self, payload: Dict[str, Any]) -> Dict[str, str]:
        cypher = build_graph_retrieval_cypher(
            payload.get("dish_match_results", []),
            resolve_diseases_from_payload(payload),
        )
        validate_read_only_cypher(cypher)
        return {
            "cypher": cypher,
            "question_type": payload.get("question_type") or "single_dish",
            "rationale": "Generated from full request payload, dish match scores, fallback strategies, and chronic diseases.",
        }


def normalize_request_payload(
    *,
    question: str,
    question_type: QuestionType,
    user_profile: UserProfile,
    health_condition: HealthCondition,
    weekly_diet_records: List[DietRecord],
    dish_candidates: Optional[List[str]] = None,
    dish_match_results: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    return {
        "question": question,
        "question_type": question_type,
        "user_profile": user_profile.model_dump(),
        "health_condition": health_condition.model_dump(),
        "weekly_diet_records_summary": summarize_weekly_records_for_retrieval(weekly_diet_records),
        "dish_candidates": dish_candidates or [],
        "dish_match_results": dish_match_results or [],
    }


def summarize_weekly_records_for_retrieval(records: List[DietRecord]) -> Dict[str, Any]:
    dish_names = [record.dish_name for record in records if record.dish_name]
    notes = [record.note for record in records if record.note]
    return {
        "record_count": len(records),
        "recent_dish_names": dish_names[:10],
        "note_keywords": extract_note_keywords(notes),
    }


def extract_note_keywords(notes: List[str]) -> List[str]:
    keywords = []
    for token in ("炸", "油", "鹹", "醬", "甜", "糖", "蔬菜", "沙拉", "湯", "起司", "奶油"):
        if any(token in note for note in notes):
            keywords.append(token)
    return keywords


def infer_question_type(question: str, request_question_type: Optional[QuestionType] = None) -> QuestionType:
    comparison_markers = ("還是", "或", "或是", "或者", "vs", "VS", "比較", "哪個", "哪一個", "哪一道")
    if any(marker in question for marker in comparison_markers):
        return "dish_comparison"
    if request_question_type in ("single_dish", "dish_comparison", "unknown"):
        return request_question_type
    return "single_dish"


def extract_dish_candidates(payload: Dict[str, Any]) -> List[str]:
    structured = payload.get("selected_dishes")
    if isinstance(structured, list):
        return dedupe_candidates([str(item) for item in structured])

    question = str(payload.get("question") or "")
    question_type = payload.get("question_type")
    cleaned = question
    for token in (
        "你覺得",
        "我今天要吃",
        "今天要吃",
        "我要吃",
        "我想吃",
        "適合吃",
        "適合",
        "請問",
        "可以吃",
        "能吃",
        "嗎",
        "呢",
        "？",
        "?",
    ):
        cleaned = cleaned.replace(token, " ")

    if question_type == "dish_comparison":
        parts = re.split(r"還是|或是|或者|或|跟|和|、|,|，|/|\s+vs\s+|\s+VS\s+|\s*v\.s\.\s*", cleaned)
    else:
        parts = [cleaned]

    candidates = []
    for part in parts:
        candidate = re.sub(r"\s+", "", part)
        candidate = candidate.strip("。.!！:：；;")
        candidate = prune_leading_context(candidate)
        if is_usable_candidate(candidate):
            candidates.append(candidate)
    return dedupe_candidates(candidates)


def prune_leading_context(candidate: str) -> str:
    for marker in ("有糖尿病", "有高血壓", "糖尿病", "高血壓", "慢性病"):
        candidate = candidate.replace(marker, "")
    return candidate.strip()


def is_usable_candidate(candidate: str) -> bool:
    generic_names = {"便當", "餐", "料理", "食物", "東西", "飯", "麵"}
    return len(candidate) >= 2 and candidate not in generic_names


def dedupe_candidates(candidates: List[str]) -> List[str]:
    deduped = []
    for candidate in candidates:
        candidate = candidate.strip()
        if candidate and candidate not in deduped:
            deduped.append(candidate)
    if len(deduped) > 1:
        deduped = [name for name in deduped if not any(name != other and name in other for other in deduped)]
    return deduped


def resolve_diseases_from_payload(payload: Dict[str, Any]) -> List[str]:
    health_condition = payload.get("health_condition") or {}
    if health_condition.get("has_chronic_disease") and health_condition.get("chronic_diseases"):
        return [str(name) for name in health_condition["chronic_diseases"] if str(name).strip()]
    return []


def build_graph_retrieval_cypher(match_results: List[Dict[str, Any]], disease_names: List[str]) -> str:
    targets = [
        {
            "input_name": item["input_name"],
            "matched_dish_name": item["matched_dish_name"],
            "retrieval_strategy": item["retrieval_strategy"],
        }
        for item in match_results
        if item.get("retrieval_strategy") in {"dish_match", "ingredient_fallback"}
    ]

    if not targets:
        raise ValueError("No dish candidates are available for graph retrieval.")

    disease_literal = json.dumps(disease_names, ensure_ascii=False)
    return f"""
UNWIND {cypher_literal(targets)} AS target
OPTIONAL MATCH (d:Dish)-[c:CONTAINS]->(dish_ing:Ingredient)
WHERE target.retrieval_strategy = "dish_match"
  AND d.name = target.matched_dish_name
OPTIONAL MATCH (fallback_ing:Ingredient)
WHERE target.retrieval_strategy = "ingredient_fallback"
  AND (target.input_name CONTAINS fallback_ing.name OR fallback_ing.name CONTAINS target.input_name)
WITH target, d, c, coalesce(dish_ing, fallback_ing) AS ing
WHERE ing IS NOT NULL
MATCH (ing)-[hn:HAS_NUTRITION]->(n:Nutrition)
OPTIONAL MATCH (dis:Disease)-[rule:HAS_DIET_RULE]->(n)
WHERE dis.name IN {disease_literal}
OPTIONAL MATCH (f:FoodItem {{food_id: hn.source_food_id}})
WHERE c IS NULL OR c.matched_food_id IS NULL OR hn.source_food_id = c.matched_food_id
RETURN
  target.input_name AS dish_name,
  d.name AS matched_dish_name,
  target.retrieval_strategy AS retrieval_strategy,
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
ORDER BY dish_name, retrieval_strategy, ingredient_name, nutrition_name
LIMIT {GRAPH_QUERY_LIMIT}
""".strip()


def cypher_literal(items: List[Dict[str, Any]]) -> str:
    chunks = []
    for item in items:
        props = []
        for key, value in item.items():
            props.append(f"{key}: {json.dumps(value, ensure_ascii=False)}")
        chunks.append("{" + ", ".join(props) + "}")
    return "[" + ", ".join(chunks) + "]"


def nutrition_structured_schema() -> Dict[str, Any]:
    return {
        "schema": GRAPH_SCHEMA,
    }
