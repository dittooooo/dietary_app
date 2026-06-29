from __future__ import annotations

import re
from typing import Any, Dict, List

from .config import DISH_MATCH_THRESHOLD


CULINARY_VARIANT_REPLACEMENTS = (
    ("豚骨", "豬肉"),
    ("豚", "豬"),
)


class DishMatcher:
    def __init__(self, driver: Any, *, threshold: int = DISH_MATCH_THRESHOLD) -> None:
        self.driver = driver
        self.threshold = threshold

    def match_dishes(self, candidates: List[str]) -> List[Dict[str, Any]]:
        cleaned_candidates = []
        for candidate in candidates:
            candidate = candidate.strip()
            if candidate and candidate not in cleaned_candidates:
                cleaned_candidates.append(candidate)
        if not cleaned_candidates:
            return []

        variant_rows = [
            {"raw_input_name": candidate, "input_name": variant}
            for candidate in cleaned_candidates
            for variant in candidate_variants(candidate)
        ]
        query = """
        UNWIND $variants AS candidate
        OPTIONAL MATCH (d:Dish)
        WHERE d.name = candidate.input_name
           OR d.name CONTAINS candidate.input_name
           OR candidate.input_name CONTAINS d.name
        OPTIONAL MATCH (d)-[dish_amount:CONTAINS]->(:Ingredient)
        WITH candidate, candidate.raw_input_name AS raw_input_name, candidate.input_name AS input_name, d,
             max(CASE
               WHEN dish_amount.unit IN ["克", "g", "公克"] THEN coalesce(dish_amount.amount_per_serving, dish_amount.amount, 0)
               ELSE 0
             END) AS max_solid_amount_per_serving
        WITH candidate, raw_input_name, input_name, d, max_solid_amount_per_serving,
             CASE
               WHEN d.name = candidate.input_name THEN 110 + size(candidate.input_name)
               WHEN d.name CONTAINS candidate.input_name THEN 80 + size(candidate.input_name) - (size(d.name) - size(candidate.input_name))
               WHEN candidate.input_name CONTAINS d.name THEN 60 + size(d.name)
               ELSE 0
             END
             + CASE
                 WHEN candidate.input_name <> candidate.raw_input_name
                      AND (candidate.raw_input_name CONTAINS "拉麵" OR candidate.raw_input_name CONTAINS "麵")
                      AND d.name CONTAINS "日式" THEN 4
                 ELSE 0
               END
             + CASE
                 WHEN candidate.input_name <> candidate.raw_input_name
                      AND candidate.raw_input_name CONTAINS "拉麵"
                      AND d.name CONTAINS "叉燒" THEN 4
                 ELSE 0
               END
             - CASE
                 WHEN d.name <> candidate.input_name
                      AND d.name <> candidate.raw_input_name
                      AND max_solid_amount_per_serving >= 500
                 THEN 30
                 ELSE 0
               END AS score
        WITH candidate, raw_input_name, input_name,
             CASE WHEN d IS NULL THEN [] ELSE [{
               type: "dish",
               input_name: input_name,
               name: d.name,
               food_id: null,
               score: score,
               extra_length: abs(size(d.name) - size(input_name))
             }] END AS dish_matches
        OPTIONAL MATCH (f:FoodItem)
        WHERE f.name = candidate.input_name
           OR f.name CONTAINS candidate.input_name
           OR candidate.input_name CONTAINS f.name
        WITH raw_input_name, dish_matches,
             collect(CASE
               WHEN f IS NULL THEN null
               ELSE {
                 type: "food_item",
                 input_name: input_name,
                 name: f.name,
                 food_id: f.food_id,
                 score: CASE
                   WHEN f.name = input_name THEN 90 + size(input_name)
                   WHEN f.name CONTAINS input_name THEN 70 + size(input_name) - (size(f.name) - size(input_name))
                   WHEN input_name CONTAINS f.name THEN 60 + size(f.name)
                   ELSE 0
                 END
                 + CASE WHEN f.category = "沖泡飲品類" THEN 20 ELSE 0 END
                 - CASE
                     WHEN raw_input_name <> input_name
                          AND f.name = input_name
                          AND (raw_input_name ENDS WITH input_name OR raw_input_name CONTAINS input_name)
                     THEN 35
                     ELSE 0
                   END,
                 extra_length: abs(size(f.name) - size(input_name))
               }
             END) AS raw_food_matches
        WITH raw_input_name, dish_matches + [item IN raw_food_matches WHERE item IS NOT NULL] AS matches
        UNWIND matches AS match
        WITH raw_input_name, match
        WHERE match.name IS NOT NULL
        ORDER BY raw_input_name, match.score DESC, match.extra_length ASC, size(match.name) ASC, match.name
        WITH raw_input_name, collect(match)[0] AS best
        RETURN
          raw_input_name,
          best.input_name AS input_name,
          best.type AS match_type,
          CASE WHEN best.type = "dish" THEN best.name ELSE null END AS matched_dish_name,
          CASE WHEN best.type = "food_item" THEN best.name ELSE null END AS matched_food_name,
          best.food_id AS matched_food_id,
          best.score AS match_score
        ORDER BY raw_input_name
        """
        with self.driver.session() as session:
            rows = [dict(row) for row in session.run(query, variants=variant_rows)]

        found_inputs = {row["raw_input_name"] for row in rows}
        for candidate in cleaned_candidates:
            if candidate not in found_inputs:
                rows.append(
                    {
                        "raw_input_name": candidate,
                        "input_name": candidate,
                        "matched_dish_name": None,
                        "match_score": 0,
                    }
                )

        results: List[Dict[str, Any]] = []
        for row in rows:
            score = int(row.get("match_score") or 0)
            matched_name = row.get("matched_dish_name")
            matched_food_name = row.get("matched_food_name")
            matched_food_id = row.get("matched_food_id")
            match_type = row.get("match_type")
            if match_type == "dish" and matched_name and score >= self.threshold:
                strategy = "dish_match"
            elif match_type == "food_item" and matched_food_id and score >= self.threshold:
                strategy = "fooditem_fallback"
            else:
                strategy = "ingredient_fallback"
            if strategy == "dish_match" and matched_name == row["input_name"]:
                reason = "exact dish match"
            elif strategy == "fooditem_fallback" and matched_food_name == row["input_name"]:
                reason = "exact food item match"
            elif strategy in {"dish_match", "fooditem_fallback"}:
                reason = "name similarity"
            else:
                reason = "below threshold"
            results.append(
                {
                    "input_name": row.get("raw_input_name") or row["input_name"],
                    "raw_input_name": row.get("raw_input_name") or row["input_name"],
                    "matched_query_name": row["input_name"],
                    "matched_dish_name": matched_name if strategy == "dish_match" else None,
                    "matched_food_id": matched_food_id if strategy == "fooditem_fallback" else None,
                    "matched_food_name": matched_food_name if strategy == "fooditem_fallback" else None,
                    "match_score": score,
                    "match_reason": reason,
                    "retrieval_strategy": strategy,
                }
            )
        return results


def candidate_variants(candidate: str) -> List[str]:
    normalized = re.sub(r"\s+", "", candidate).strip("。.!！:：；;，,、？?")
    if not normalized:
        return []

    variants = [normalized]
    for old, new in CULINARY_VARIANT_REPLACEMENTS:
        if old in normalized:
            semantic_variant = normalized.replace(old, new)
            if semantic_variant not in variants:
                variants.append(semantic_variant)

    max_len = min(len(normalized), 8)
    bases = list(variants)
    for base in bases:
        max_len = min(len(base), 8)
        for size in range(max_len, 1, -1):
            for start in range(0, len(base) - size + 1):
                variant = base[start : start + size]
                if is_meaningful_variant(variant) and variant not in variants:
                    variants.append(variant)
    return variants[:40]


def is_meaningful_variant(variant: str) -> bool:
    generic_variants = {
        "我想",
        "想吃",
        "可以",
        "可不",
        "不可以",
        "好嗎",
        "如何",
        "怎樣",
        "怎麼樣",
        "晚餐",
        "午餐",
        "早餐",
        "今天",
        "明天",
    }
    return len(variant) >= 2 and variant not in generic_variants
