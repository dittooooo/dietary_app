"""Resolve ingredient mapping conflict rows using current FoodItem names/aliases.

This is intentionally conservative: a row is approved only when exactly one
candidate has an exact normalized name or alias match. All other rows are
marked needs_review and their previous manual-looking selection is cleared.
The script does not modify Neo4j.
"""

from __future__ import annotations

import argparse
import csv
import json
import shutil
import unicodedata
from pathlib import Path
from typing import Any, Dict, Iterable, List, Set

from neo4j import GraphDatabase

try:
    from .knowledge_agent_importer import NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER
except ImportError:  # pragma: no cover - allows direct script execution
    from knowledge_agent_importer import NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER


DEFAULT_INPUT_PATH = Path(__file__).resolve().parent / "output" / "ingredient_mapping_conflicts.csv"
DEFAULT_BACKUP_PATH = DEFAULT_INPUT_PATH.with_name(
    "ingredient_mapping_conflicts_before_auto_resolution.csv"
)


def normalize_text(value: Any) -> str:
    """Normalize Unicode and remove spacing/punctuation for exact comparison."""
    text = unicodedata.normalize("NFKC", str(value or "")).strip().casefold()
    return "".join(char for char in text if unicodedata.category(char)[0] not in {"Z", "P", "S"})


def split_pipe(value: Any) -> List[str]:
    return [part.strip() for part in str(value or "").split("|")]


def alias_values(value: Any) -> Iterable[str]:
    """Handle list properties, JSON arrays, or common delimited alias strings."""
    if value is None:
        return []
    if isinstance(value, (list, tuple, set)):
        return [str(item).strip() for item in value if str(item).strip()]

    text = str(value).strip()
    if not text:
        return []
    try:
        parsed = json.loads(text)
    except (TypeError, ValueError, json.JSONDecodeError):
        parsed = None
    if isinstance(parsed, list):
        return [str(item).strip() for item in parsed if str(item).strip()]
    return [part.strip() for part in text.replace("，", ",").replace("、", ",").replace("；", ";").split(",") for part in part.split(";") if part.strip()]


def load_food_items(uri: str, user: str, password: str, food_ids: Set[str]) -> Dict[str, Dict[str, Any]]:
    query = """
    MATCH (f:FoodItem)
    WHERE f.food_id IN $food_ids
    RETURN f.food_id AS food_id,
           f.name AS name,
           f.alias AS alias,
           f.aliases AS aliases
    """
    with GraphDatabase.driver(uri, auth=(user, password)) as driver:
        driver.verify_connectivity()
        with driver.session() as session:
            return {
                str(row["food_id"]): row
                for row in session.run(query, food_ids=sorted(food_ids))
                if row.get("food_id")
            }


def resolve_rows(rows: List[Dict[str, str]], food_items: Dict[str, Dict[str, Any]]) -> Dict[str, int]:
    stats = {"approved": 0, "needs_review": 0, "needs_review_with_suggestion": 0}

    for row in rows:
        original = row.get("original_name", "").strip()
        original_key = normalize_text(original)
        candidate_ids = [candidate for candidate in split_pipe(row.get("candidate_food_ids")) if candidate]
        candidate_names = split_pipe(row.get("candidate_food_names"))

        exact_matches: List[tuple[str, str, str]] = []
        lexical_matches: List[tuple[str, str]] = []
        for index, food_id in enumerate(candidate_ids):
            item = food_items.get(food_id, {})
            food_name = str(item.get("name") or (candidate_names[index] if index < len(candidate_names) else "")).strip()
            if normalize_text(food_name) == original_key and original_key:
                exact_matches.append((food_id, food_name, "exact FoodItem name match"))
                continue

            aliases: List[str] = []
            aliases.extend(alias_values(item.get("alias")))
            aliases.extend(alias_values(item.get("aliases")))
            if original_key and any(normalize_text(alias) == original_key for alias in aliases):
                exact_matches.append((food_id, food_name, "exact FoodItem alias match"))

            candidate_key = normalize_text(food_name)
            if (
                candidate_key
                and candidate_key != original_key
                and len(candidate_key) >= 2
                and candidate_key in original_key
            ):
                lexical_matches.append((food_id, food_name))

        if len(exact_matches) == 1:
            food_id, food_name, reason = exact_matches[0]
            row["selected_food_id"] = food_id
            row["selected_food_name"] = food_name
            row["decision"] = "approved"
            row["note"] = reason
            stats["approved"] += 1
        elif len(lexical_matches) == 1:
            food_id, food_name = lexical_matches[0]
            row["selected_food_id"] = food_id
            row["selected_food_name"] = food_name
            row["decision"] = "needs_review"
            row["note"] = "Unique lexical base-name suggestion; verify preparation/state and FoodItem identity"
            stats["needs_review"] += 1
            stats["needs_review_with_suggestion"] += 1
        else:
            row["selected_food_id"] = ""
            row["selected_food_name"] = ""
            row["decision"] = "needs_review"
            if len(exact_matches) > 1:
                row["note"] = "Multiple candidates have an exact name/alias match; manual review required"
            else:
                row["note"] = "No unique exact FoodItem name/alias match; manual review required"
            stats["needs_review"] += 1

    return stats


def write_csv(rows: List[Dict[str, str]], path: Path) -> None:
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
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="Resolve ingredient mapping conflicts from current Neo4j FoodItems.")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT_PATH)
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--no-backup", action="store_true")
    args = parser.parse_args()

    input_path = args.input.resolve()
    output_path = (args.output or input_path).resolve()
    if not input_path.exists():
        raise FileNotFoundError(input_path)

    with input_path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"No conflict rows found in {input_path}")

    food_ids = {
        candidate
        for row in rows
        for candidate in split_pipe(row.get("candidate_food_ids"))
        if candidate
    }
    food_items = load_food_items(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD, food_ids)
    stats = resolve_rows(rows, food_items)

    if output_path == input_path and not args.no_backup and not DEFAULT_BACKUP_PATH.exists():
        shutil.copy2(input_path, DEFAULT_BACKUP_PATH)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    write_csv(rows, output_path)

    print(json.dumps({"rows": len(rows), "food_items_loaded": len(food_items), **stats, "output": str(output_path)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
