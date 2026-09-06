from __future__ import annotations

import re


WRITE_KEYWORDS = re.compile(
    r"\b(CREATE|MERGE|SET|DELETE|DETACH|REMOVE|DROP|LOAD\s+CSV|CALL|APOC|"
    r"CREATE\s+INDEX|CREATE\s+CONSTRAINT|ALTER|GRANT|DENY|REVOKE|START|INSERT|FINISH)\b",
    re.IGNORECASE,
)

REQUIRED_NUTRITION_RETURN_ALIASES = {
    "dish_name",
    "matched_name",
    "matched_type",
    "matched_dish_name",
    "match_score",
    "match_reason",
    "retrieval_strategy",
    "ingredient_name",
    "food_item_name",
    "nutrition_name",
    "nutrition_name_zh",
    "nutrition_category",
    "amount_per_serving",
    "amount_per_100g",
    "nutrition_unit",
    "disease_name",
    "diet_rule_relation",
    "diet_rule_direction",
    "diet_rule_note",
    "diet_rule_reason",
    "food_level_condition",
    "sources_json",
}


# 檢查 Cypher 是否只讀、單一語句，且一定有 RETURN 與 LIMIT。
def validate_read_only_cypher(cypher: str) -> None:
    if not cypher.strip():
        raise ValueError("Cypher is empty.")
    if ";" in cypher.strip().rstrip(";"):
        raise ValueError("Cypher contains multiple statements.")
    if WRITE_KEYWORDS.search(cypher):
        raise ValueError(f"Cypher is not read-only:\n{cypher}")
    if not re.match(r"^\s*(MATCH|OPTIONAL\s+MATCH|UNWIND)\b", cypher, re.IGNORECASE):
        raise ValueError("Cypher must start with MATCH, OPTIONAL MATCH, or UNWIND.")
    if not re.search(r"\bRETURN\b", cypher, re.IGNORECASE):
        raise ValueError("Cypher must contain RETURN.")
    if not re.search(r"\bLIMIT\b", cypher, re.IGNORECASE):
        raise ValueError("Cypher must contain LIMIT.")


def validate_nutrition_return_schema(cypher: str) -> None:
    validate_read_only_cypher(cypher)
    if re.search(r":\s*`?(Disease|HAS_DIET_RULE)\b", cypher, re.IGNORECASE):
        raise ValueError("Disease rules must be retrieved separately from nutrition totals.")
    aliases = set(re.findall(r"\bAS\s+`?([A-Za-z_][A-Za-z0-9_]*)`?", cypher, re.IGNORECASE))
    missing = sorted(REQUIRED_NUTRITION_RETURN_ALIASES - aliases)
    if missing:
        raise ValueError(f"Cypher is missing required RETURN aliases: {', '.join(missing)}")


def validate_nutrition_rows(rows: list[dict]) -> None:
    for index, row in enumerate(rows):
        missing = sorted(REQUIRED_NUTRITION_RETURN_ALIASES - set(row.keys()))
        if missing:
            raise ValueError(f"Nutrition row {index} is missing required fields: {', '.join(missing)}")
