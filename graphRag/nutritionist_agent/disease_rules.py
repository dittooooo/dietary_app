"""Retrieve profile and question-mentioned rules without inferring a diagnosis."""
from __future__ import annotations

import json
import math
import operator
from typing import Any

from .models import HealthCondition


RULE_QUERY = """
UNWIND $diseases AS requested
OPTIONAL MATCH (d:Disease {name: requested})
OPTIONAL MATCH (d)-[r:HAS_DIET_RULE]->(n:Nutrition)
RETURN requested, d.name AS disease, properties(r) AS rule,
       properties(n) AS nutrient, elementId(r) AS rule_id
ORDER BY requested, rule_id
LIMIT 2001
""".strip()


def active_diseases(health: HealthCondition) -> list[str]:
    if not health.has_chronic_disease:
        return []
    return list(dict.fromkeys(name.strip() for name in health.chronic_diseases if name.strip()))


def retrieve_disease_rules(retriever: Any, health: HealthCondition, question: str = "") -> list[dict]:
    profile_names = active_diseases(health)
    question_names = []
    if question.strip():
        mentions = retriever.retrieve(
            "MATCH (d:Disease) WHERE d.name IS NOT NULL AND trim(d.name) <> '' "
            "AND toLower($question) CONTAINS toLower(d.name) "
            "RETURN DISTINCT d.name AS name ORDER BY name LIMIT 2001",
            {"question": question},
        )
        if len(mentions) > 2000:
            raise RuntimeError("Disease mentions exceeded safety limit; refusing partial evidence.")
        question_names = [row["name"] for row in mentions]
    names = list(dict.fromkeys(question_names + profile_names))
    missing = ([{"requested": None, "status": "missing_disease_name", "rules": [],
                 "context_sources": ["profile"]}]
               if health.has_chronic_disease and not profile_names else [])
    if not names:
        return missing
    rows = retriever.retrieve(RULE_QUERY, {"diseases": names})
    if len(rows) > 2000:
        raise RuntimeError("Disease rule result exceeded safety limit; refusing partial evidence.")
    groups = {name: {"requested": name, "status": "disease_not_found", "rules": [],
                     "context_sources": [source for source, source_names in
                                         (("question", question_names), ("profile", profile_names))
                                         if name in source_names]} for name in names}
    for row in rows:
        group = groups[row["requested"]]
        if row.get("disease"):
            group["status"] = "rules_found" if row.get("rule") else "no_rules"
        if row.get("rule"):
            group["rules"].append({
                "id": row["rule_id"], "nutrient": row["nutrient"], **row["rule"],
            })
    return list(groups.values()) + missing


def parse_json(value: Any, default: Any) -> Any:
    if value is None:
        return default
    if not isinstance(value, str):
        return value
    try:
        return json.loads(value)
    except (ValueError, TypeError):
        return default


def finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def convert_unit(value: Any, source: str | None, target: str | None) -> float | None:
    if not finite_number(value) or value < 0:
        return None
    if source == target and source in {"g", "mg", "kcal"}:
        return float(value)
    factors = {"g": 1.0, "mg": 0.001}
    if source in factors and target in factors:
        return value * factors[source] / factors[target]
    return None


# These conditions can be checked using the named nutrient alone.
# GI, added sugar, symptom triggers, fat ratios and stage-dependent rules cannot.
DIRECT_CONDITIONS = {
    "high_sodium", "high_saturated_fat", "high_fiber", "high_cholesterol",
    "calcium_rich", "magnesium_source", "high_phosphorus", "trans_fat_containing",
}
OPS = {">": operator.gt, ">=": operator.ge, "<": operator.lt, "<=": operator.le, "=": operator.eq}


def evaluate_rule(rule: dict, food_rows: list[dict]) -> dict:
    result = {"rule_id": rule["id"], "assessment": "insufficient", "scope": "ingredient_per_100g",
              "matched_foods": [], "reason": "缺少可比較的每百克食材資料"}
    spec = parse_json(rule.get("food_level_rule_json"), {})
    criteria = spec.get("criteria", []) if isinstance(spec, dict) else []
    condition = rule.get("food_level_condition")
    if rule.get("direction") == "adjust_by_stage" or condition == "high_potassium":
        return {**result, "reason": "需確認分期、腎功能、用藥或個別限制，不能自動建議增加"}
    if condition not in DIRECT_CONDITIONS or not isinstance(criteria, list) or len(criteria) != 1:
        return {**result, "reason": "此條件需額外資料；不以總糖代替添加糖、不以碳水量推算GI"}
    criterion = criteria[0]
    if (not isinstance(criterion, dict) or criterion.get("metric") != "food_level"
            or criterion.get("basis", spec.get("basis")) != "per_100g"
            or criterion.get("operator") not in OPS or not finite_number(criterion.get("value"))):
        return {**result, "reason": "規則基準或運算不支援；不可套用每日或百分比門檻"}
    checked, matched = set(), set()
    for row in food_rows:
        food = row.get("food_item_name")
        value = convert_unit(row.get("amount_per_100g"), row.get("nutrition_unit"), criterion.get("unit"))
        if not food or value is None:
            continue
        checked.add(food)
        if OPS[criterion["operator"]](value, criterion["value"]):
            matched.add(food)
    if not checked:
        return result
    status = "not_triggered"
    if matched:
        status = "potential_conflict" if rule.get("relation") in {"limit", "prohibit"} else "support_signal"
    return {**result, "assessment": status, "matched_foods": sorted(matched),
            "reason": "僅為對應食材觸發規則的訊號，不代表整道料理或整日符合/違反醫療要求"}
