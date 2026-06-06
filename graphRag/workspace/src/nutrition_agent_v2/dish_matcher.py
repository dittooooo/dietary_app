from __future__ import annotations

from typing import Any, Dict, List

from .config import DISH_MATCH_THRESHOLD


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

        query = """
        UNWIND $candidates AS candidate
        OPTIONAL MATCH (d:Dish)
        WHERE d.name = candidate
           OR d.name CONTAINS candidate
           OR candidate CONTAINS d.name
        WITH candidate, d,
             CASE
               WHEN d.name = candidate THEN 100
               WHEN d.name CONTAINS candidate THEN 85
               WHEN candidate CONTAINS d.name THEN 70
               ELSE 0
             END AS score
        ORDER BY candidate, score DESC, size(d.name) DESC
        WITH candidate, collect({name: d.name, score: score})[0] AS best
        RETURN
          candidate AS input_name,
          best.name AS matched_dish_name,
          coalesce(best.score, 0) AS match_score
        ORDER BY input_name
        """
        with self.driver.session() as session:
            rows = [dict(row) for row in session.run(query, candidates=cleaned_candidates)]

        found_inputs = {row["input_name"] for row in rows}
        for candidate in cleaned_candidates:
            if candidate not in found_inputs:
                rows.append(
                    {
                        "input_name": candidate,
                        "matched_dish_name": None,
                        "match_score": 0,
                    }
                )

        results: List[Dict[str, Any]] = []
        for row in rows:
            score = int(row.get("match_score") or 0)
            matched_name = row.get("matched_dish_name")
            strategy = "dish_match" if matched_name and score >= self.threshold else "ingredient_fallback"
            reason = "exact match" if score == 100 else "name similarity" if strategy == "dish_match" else "below threshold"
            results.append(
                {
                    "input_name": row["input_name"],
                    "matched_dish_name": matched_name if strategy == "dish_match" else None,
                    "match_score": score,
                    "match_reason": reason,
                    "retrieval_strategy": strategy,
                }
            )
        return results
