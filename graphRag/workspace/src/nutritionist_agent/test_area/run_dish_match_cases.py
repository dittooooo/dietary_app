from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Any, Dict, List


TEST_AREA = Path(__file__).resolve().parent
WORKSPACE = TEST_AREA.parents[2]
GOLD_PATH = TEST_AREA / "dish_match_gold.csv"
DEFAULT_OUTPUT_PATH = TEST_AREA / "output" / "dish_match_results.jsonl"

if str(WORKSPACE) not in sys.path:
    sys.path.insert(0, str(WORKSPACE))


def load_gold(path: Path) -> List[Dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    required = {
        "case_id",
        "input_name",
        "expected_label",
        "expected_dish_name",
        "acceptable_dish_names",
        "review_status",
    }
    missing = required - set(rows[0].keys() if rows else [])
    if missing:
        raise ValueError(f"Gold file is missing columns: {sorted(missing)}")
    return rows


def run_cases(gold_rows: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    from neo4j import GraphDatabase

    from src.nutritionist_agent.config import NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER
    from src.nutritionist_agent.dish_matcher import DishMatcher

    driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
    try:
        driver.verify_connectivity()
        matcher = DishMatcher(driver)
        inputs = [row["input_name"] for row in gold_rows if row["input_name"].strip()]
        matches = matcher.match_dishes(inputs)
    finally:
        driver.close()

    matches_by_input = {str(item.get("input_name")): item for item in matches}
    results = []
    for gold in gold_rows:
        predicted = matches_by_input.get(gold["input_name"], {})
        results.append(
            {
                "case_id": gold["case_id"],
                "input_name": gold["input_name"],
                "expected_label": gold["expected_label"],
                "expected_dish_name": gold["expected_dish_name"],
                "acceptable_dish_names": gold["acceptable_dish_names"],
                "review_status": gold["review_status"],
                "predicted_dish_name": predicted.get("matched_dish_name"),
                "predicted_food_name": predicted.get("matched_food_name"),
                "predicted_match_score": predicted.get("match_score"),
                "predicted_bm25_score": predicted.get("bm25_score"),
                "predicted_match_status": predicted.get("match_status"),
                "predicted_match_reason": predicted.get("match_reason"),
                "predicted_strategy": predicted.get("retrieval_strategy"),
            }
        )
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the current DishMatcher against the gold cases.")
    parser.add_argument("--gold", type=Path, default=GOLD_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--validate-only", action="store_true", help="Validate the gold file without Neo4j.")
    args = parser.parse_args()

    gold_rows = load_gold(args.gold)
    pending = sum(row["review_status"].strip().lower() != "approved" for row in gold_rows)
    print(f"Loaded {len(gold_rows)} gold cases; {pending} require manual review.")

    if args.validate_only:
        print("Gold file validation passed.")
        return 0

    try:
        results = run_cases(gold_rows)
    except Exception as exc:
        print("Unable to run DishMatcher. Make sure Neo4j is running and .env is configured.", file=sys.stderr)
        print(f"Reason: {exc}", file=sys.stderr)
        return 2

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as handle:
        for result in results:
            handle.write(json.dumps(result, ensure_ascii=False) + "\n")
    print(f"Wrote {len(results)} match results to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
