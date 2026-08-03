from __future__ import annotations

import argparse
import json
import sys
import zipfile
from pathlib import Path
from typing import Any, Dict, List, Tuple
from xml.etree import ElementTree as ET


CURRENT_DIR = Path(__file__).resolve().parent
WORKSPACE_DIR = CURRENT_DIR.parents[2]
DEFAULT_REPORT_PATH = CURRENT_DIR / "nutrition_validation_report_regenerated.ods"
DEFAULT_OUTPUT_PATH = CURRENT_DIR / "issue_recipe_details_from_validation_report.json"
DEFAULT_SOURCE_PATHS = [
    WORKSPACE_DIR / "data" / "recipe_and_nutrition" / "food_and_nutrition_mapping.json",
    WORKSPACE_DIR / "src" / "recipes" / "new_recipe_and_nutrition_mapping_restaurant_tku_20260609.json",
]

NS = {
    "table": "urn:oasis:names:tc:opendocument:xmlns:table:1.0",
    "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT_PATH)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--source", type=Path, action="append", dest="sources")
    args = parser.parse_args()

    report_path = resolve_path(args.report)
    output_path = resolve_path(args.output)
    source_paths = [resolve_path(path) for path in (args.sources or DEFAULT_SOURCE_PATHS)]

    issue_rows = read_issue_rows(report_path)
    issue_recipe_ids = [row["recipe_id"] for row in issue_rows if row.get("recipe_id")]
    recipes, missing_ids = collect_recipes_by_id(issue_recipe_ids, source_paths)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(recipes, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"有 issue 的料理數: {len(issue_recipe_ids)}")
    print(f"成功抓出完整食譜數: {len(recipes)}")
    print(f"找不到食譜資料數: {len(missing_ids)}")
    print(f"輸出位置: {output_path}")


def resolve_path(path: Path) -> Path:
    if path.is_absolute():
        return path
    return CURRENT_DIR / path


def read_issue_rows(report_path: Path) -> List[Dict[str, str]]:
    rows = read_ods_sheet(report_path, "DishValidation")
    if not rows:
        return []
    headers = rows[0]
    issue_rows: List[Dict[str, str]] = []
    for row in rows[1:]:
        item = {header: row[index] if index < len(row) else "" for index, header in enumerate(headers)}
        status = item.get("validation_status", "")
        issue_type = item.get("issue_type", "")
        if status and status != "PASS" or issue_type:
            issue_rows.append(item)
    return issue_rows


def read_ods_sheet(report_path: Path, sheet_name: str) -> List[List[str]]:
    with zipfile.ZipFile(report_path) as ods:
        content = ods.read("content.xml")
    root = ET.fromstring(content)
    for table in root.findall(".//table:table", NS):
        if table.attrib.get(f"{{{NS['table']}}}name") != sheet_name:
            continue
        return [read_ods_row(row) for row in table.findall("table:table-row", NS)]
    raise ValueError(f"Sheet not found: {sheet_name}")


def read_ods_row(row: ET.Element) -> List[str]:
    values: List[str] = []
    for cell in row.findall("table:table-cell", NS):
        repeated = int(cell.attrib.get(f"{{{NS['table']}}}number-columns-repeated", "1"))
        text = "".join(cell.itertext())
        values.extend([text] * repeated)
    while values and values[-1] == "":
        values.pop()
    return values


def collect_recipes_by_id(recipe_ids: List[str], source_paths: List[Path]) -> Tuple[List[Dict[str, Any]], List[str]]:
    wanted = set(recipe_ids)
    found: Dict[str, Dict[str, Any]] = {}

    for source_path in source_paths:
        data = json.loads(source_path.read_text(encoding="utf-8"))
        for recipe in iter_recipe_objects(data):
            recipe_id = str(recipe.get("recipe_id") or "").strip()
            if recipe_id in wanted and recipe_id not in found:
                found[recipe_id] = recipe

    recipes = []
    for recipe_id in recipe_ids:
        recipe = found.get(recipe_id)
        if recipe is None:
            continue
        recipes.append(recipe)

    missing = [recipe_id for recipe_id in recipe_ids if recipe_id not in found]
    return recipes, missing


def iter_recipe_objects(data: Any):
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and "recipe_id" in item:
                yield item
    elif isinstance(data, dict):
        for value in data.values():
            yield from iter_recipe_objects(value)


if __name__ == "__main__":
    main()
