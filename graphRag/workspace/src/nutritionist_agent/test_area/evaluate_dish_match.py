from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, List


TEST_AREA = Path(__file__).resolve().parent
DEFAULT_RESULTS_PATH = TEST_AREA / "output" / "dish_match_results.jsonl"
DEFAULT_REPORT_PATH = TEST_AREA / "output" / "dish_match_report.json"


def load_results(path: Path) -> List[Dict[str, Any]]:
    with path.open("r", encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def normalized_names(value: str) -> set[str]:
    return {name.strip() for name in value.split("|") if name.strip()}


def evaluate_case(row: Dict[str, Any]) -> str:
    label = str(row.get("expected_label") or "").strip()
    predicted_dish = str(row.get("predicted_dish_name") or "").strip()
    predicted_food = str(row.get("predicted_food_name") or "").strip()
    strategy = str(row.get("predicted_strategy") or "").strip()

    if label in {"no_match", "unknown_restaurant_dish"}:
        if not predicted_dish and not predicted_food:
            return "correct_no_match"
        return "false_positive"

    if label == "ambiguous":
        return "manual_review"

    acceptable = normalized_names(str(row.get("acceptable_dish_names") or ""))
    if predicted_dish and predicted_dish in acceptable:
        return "correct_dish_match"
    if predicted_food:
        return "wrong_type_food_item"
    if strategy == "ingredient_fallback":
        return "missed_dish_ingredient_fallback"
    return "wrong_or_missing_dish"


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate recorded DishMatcher results.")
    parser.add_argument("--results", type=Path, default=DEFAULT_RESULTS_PATH)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT_PATH)
    args = parser.parse_args()

    rows = load_results(args.results)
    approved = [row for row in rows if str(row.get("review_status")).lower() == "approved"]
    evaluations = [{**row, "evaluation": evaluate_case(row)} for row in approved]

    counts: Dict[str, int] = {}
    for row in evaluations:
        key = row["evaluation"]
        counts[key] = counts.get(key, 0) + 1

    positive = [
        row
        for row in evaluations
        if row["expected_label"] not in {"no_match", "unknown_restaurant_dish", "ambiguous"}
    ]
    negative = [
        row
        for row in evaluations
        if row["expected_label"] in {"no_match", "unknown_restaurant_dish"}
    ]
    correct_positive = sum(row["evaluation"] == "correct_dish_match" for row in positive)
    correct_negative = sum(row["evaluation"] == "correct_no_match" for row in negative)
    false_positive = sum(row["evaluation"] == "false_positive" for row in negative)

    report = {
        "total_recorded_cases": len(rows),
        "approved_cases_evaluated": len(evaluations),
        "pending_review_cases": len(rows) - len(approved),
        "counts": counts,
        "positive_dish_accuracy": (correct_positive / len(positive)) if positive else None,
        "negative_no_match_accuracy": (correct_negative / len(negative)) if negative else None,
        "false_positive_rate": (false_positive / len(negative)) if negative else None,
        "cases": evaluations,
    }

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "cases"}, ensure_ascii=False, indent=2))
    print(f"Wrote report to {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
