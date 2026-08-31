"""Export Ingredient names that currently map to multiple FoodItems.

The generated CSV is a manual decision table. Fill selected_food_id with one
candidate FoodItem ID for each original_name before running a future repair.
"""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List

try:
    from .knowledge_agent_importer import NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER
except ImportError:  # pragma: no cover - allows direct script execution
    from knowledge_agent_importer import NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER

from neo4j import GraphDatabase


DEFAULT_OUTPUT_PATH = Path(__file__).resolve().parent / "output" / "ingredient_mapping_conflicts.csv"


def load_conflicts(uri: str, user: str, password: str) -> List[Dict[str, Any]]:
    query = """
    MATCH (i:Ingredient)-[:MAPS_TO]->(f:FoodItem)
    OPTIONAL MATCH (d:Dish)-[:CONTAINS]->(i)
    RETURN coalesce(i.original_name, i.name) AS original_name,
           i.name AS ingredient_name,
           f.food_id AS food_id,
           f.name AS food_name,
           collect(DISTINCT d.recipe_id) AS recipe_ids
    ORDER BY original_name, food_id, ingredient_name
    """

    with GraphDatabase.driver(uri, auth=(user, password)) as driver:
        driver.verify_connectivity()
        with driver.session() as session:
            rows = [record.data() for record in session.run(query)]

    grouped: Dict[str, Dict[str, Dict[str, Any]]] = defaultdict(dict)
    for row in rows:
        original_name = str(row.get("original_name") or "").strip()
        food_id = str(row.get("food_id") or "").strip()
        if not original_name or not food_id:
            continue

        candidate = grouped[original_name].setdefault(
            food_id,
            {
                "food_id": food_id,
                "food_name": str(row.get("food_name") or "").strip(),
                "ingredient_names": set(),
                "recipe_ids": set(),
            },
        )
        ingredient_name = str(row.get("ingredient_name") or "").strip()
        if ingredient_name:
            candidate["ingredient_names"].add(ingredient_name)
        candidate["recipe_ids"].update(
            str(recipe_id).strip()
            for recipe_id in (row.get("recipe_ids") or [])
            if recipe_id is not None and str(recipe_id).strip()
        )

    conflicts = []
    for original_name in sorted(grouped):
        candidates = list(grouped[original_name].values())
        if len(candidates) < 2:
            continue
        candidates.sort(key=lambda item: item["food_id"])
        conflicts.append(
            {
                "original_name": original_name,
                "candidate_count": len(candidates),
                "candidate_food_ids": " | ".join(item["food_id"] for item in candidates),
                "candidate_food_names": " | ".join(item["food_name"] for item in candidates),
                "candidate_ingredient_names": " | ".join(
                    ", ".join(sorted(item["ingredient_names"])) for item in candidates
                ),
                "candidate_dish_counts": " | ".join(
                    str(len(item["recipe_ids"])) for item in candidates
                ),
                "selected_food_id": "",
                "selected_food_name": "",
                "decision": "",
                "note": "",
            }
        )
    return conflicts


def write_csv(rows: List[Dict[str, Any]], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "original_name",
        "candidate_count",
        "candidate_food_ids",
        "candidate_food_names",
        "candidate_ingredient_names",
        "candidate_dish_counts",
        "selected_food_id",
        "selected_food_name",
        "decision",
        "note",
    ]
    with output_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export Ingredient names that map to multiple FoodItems."
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    args = parser.parse_args()

    rows = load_conflicts(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD)
    write_csv(rows, args.output)
    print(f"Exported {len(rows)} conflict groups to {args.output}")


if __name__ == "__main__":
    main()
