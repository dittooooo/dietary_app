from __future__ import annotations

import argparse
import json
import os
import sys
import zipfile
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple
from xml.sax.saxutils import escape


CURRENT_DIR = Path(__file__).resolve().parent
SRC_DIR = CURRENT_DIR.parents[1]
WORKSPACE_DIR = CURRENT_DIR.parents[2]
if str(WORKSPACE_DIR) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_DIR))

from src.nutritionist_agent.config import NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER
from src.nutritionist_agent.nutrition_calculator import NutritionCalculator, calculate_calories
from src.nutritionist_agent.retriever import GraphRetriever
from src.nutritionist_agent.text_to_cypher import build_graph_retrieval_cypher


REPORT_PATH = CURRENT_DIR / "nutrition_validation_report.ods"
DEFAULT_DISH_LIMIT = 100000

NUTRIENT_ALIASES = {
    "calories": {"熱量", "calories", "calorie", "energy", "kcal"},
    "protein_g": {"蛋白質", "protein", "protein_g"},
    "fat_g": {"脂肪", "fat", "fat_g"},
    "carbohydrate_g": {"碳水化合物", "碳水", "醣類", "carbohydrate", "carbs", "carbohydrate_g"},
    "sodium_mg": {"鈉", "sodium", "sodium_mg"},
    "sugar_g": {"糖", "糖質總量", "sugar", "sugar_g"},
}

VALIDATION_COLUMNS = [
    "recipe_id",
    "dish_name",
    "calories",
    "protein_g",
    "fat_g",
    "carbohydrate_g",
    "sodium_mg",
    "sugar_g",
    "calculated_calories",
    "calorie_difference_percent",
    "validation_status",
    "issue_type",
    "issue_description",
]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate every Dish in Neo4j using nutritionist_agent graph retrieval and nutrition calculation."
    )
    parser.add_argument("--output", type=Path, default=REPORT_PATH)
    parser.add_argument("--limit", type=int, default=None, help="Optional smoke-test limit.")
    parser.add_argument("--recipe-json", type=Path, default=None, help="Validate only recipe_ids listed in this JSON file.")
    args = parser.parse_args()

    output_path = args.output
    if not output_path.is_absolute():
        output_path = CURRENT_DIR / output_path

    validator = DishNutritionValidator(
        uri=os.getenv("NEO4J_URI", NEO4J_URI),
        user=os.getenv("NEO4J_USER", NEO4J_USER),
        password=os.getenv("NEO4J_PASSWORD", NEO4J_PASSWORD),
    )
    try:
        recipe_ids = load_recipe_ids(args.recipe_json) if args.recipe_json else None
        report_rows, summary_rows, console_summary = validator.run(limit=args.limit, recipe_ids=recipe_ids)
    finally:
        validator.close()

    write_ods(
        output_path,
        {
            "DishValidation": [VALIDATION_COLUMNS] + [[row.get(column) for column in VALIDATION_COLUMNS] for row in report_rows],
            "Summary": summary_rows,
        },
    )

    print(f"Neo4j 中料理總數: {console_summary['total_dishes']}")
    print(f"成功計算數量: {console_summary['success_count']}")
    print(f"異常資料數量: {console_summary['abnormal_count']}")
    print(f"ODS 報表輸出位置: {output_path}")


def load_recipe_ids(path: Path) -> List[str]:
    if not path.is_absolute():
        path = CURRENT_DIR / path
    data = json.loads(path.read_text(encoding="utf-8"))
    recipe_ids: List[str] = []
    if isinstance(data, list):
        for recipe in data:
            if not isinstance(recipe, dict):
                continue
            recipe_id = str(recipe.get("recipe_id") or "").strip()
            if recipe_id and recipe_id not in recipe_ids:
                recipe_ids.append(recipe_id)
    else:
        raise ValueError(f"Expected recipe JSON to be a list: {path}")
    return recipe_ids


class DishNutritionValidator:
    def __init__(self, *, uri: str, user: str, password: str) -> None:
        self.retriever = GraphRetriever(uri, user, password)
        self.calculator = NutritionCalculator()

    def close(self) -> None:
        self.retriever.close()

    def run(
        self,
        *,
        limit: Optional[int] = None,
        recipe_ids: Optional[List[str]] = None,
    ) -> Tuple[List[Dict[str, Any]], List[List[Any]], Dict[str, int]]:
        dishes = self._load_dishes(limit=limit, recipe_ids=recipe_ids)
        rows: List[Dict[str, Any]] = []
        issue_counter: Counter[str] = Counter()
        status_counter: Counter[str] = Counter()
        success_count = 0
        failure_count = 0

        for dish in dishes:
            row = self._validate_one_dish(dish)
            rows.append(row)
            status_counter[row["validation_status"]] += 1
            for issue_type in split_issue_types(row["issue_type"]):
                issue_counter[issue_type] += 1
            if row["validation_status"] == "FAIL" and row["issue_type"] in {"QUERY_ERROR", "AGENT_ERROR"}:
                failure_count += 1
            else:
                success_count += 1

        abnormal_count = sum(1 for row in rows if row["validation_status"] != "PASS")
        summary_rows = build_summary_rows(
            total_dishes=len(dishes),
            success_count=success_count,
            failure_count=failure_count,
            status_counter=status_counter,
            issue_counter=issue_counter,
        )
        console_summary = {
            "total_dishes": len(dishes),
            "success_count": success_count,
            "abnormal_count": abnormal_count,
        }
        return rows, summary_rows, console_summary

    def _load_dishes(self, *, limit: Optional[int], recipe_ids: Optional[List[str]]) -> List[Dict[str, Any]]:
        if recipe_ids is not None:
            cypher = f"""
            UNWIND {json.dumps(recipe_ids, ensure_ascii=False)} AS recipe_id
            MATCH (d:Dish {{recipe_id: recipe_id}})
            RETURN d.recipe_id AS recipe_id, d.name AS dish_name
            ORDER BY recipe_id, dish_name
            LIMIT {int(limit if limit is not None else max(DEFAULT_DISH_LIMIT, len(recipe_ids)))}
            """.strip()
            return self.retriever.retrieve(cypher)

        cypher = """
        MATCH (d:Dish)
        RETURN d.recipe_id AS recipe_id, d.name AS dish_name
        ORDER BY recipe_id, dish_name
        """.strip()
        cypher += f"\nLIMIT {int(limit if limit is not None else DEFAULT_DISH_LIMIT)}"
        return self.retriever.retrieve(cypher)

    def _validate_one_dish(self, dish: Dict[str, Any]) -> Dict[str, Any]:
        recipe_id = dish.get("recipe_id")
        dish_name = dish.get("dish_name")
        base_row = {
            "recipe_id": recipe_id,
            "dish_name": dish_name,
            "calories": None,
            "protein_g": None,
            "fat_g": None,
            "carbohydrate_g": None,
            "sodium_mg": None,
            "sugar_g": None,
            "calculated_calories": None,
            "calorie_difference_percent": None,
            "validation_status": "FAIL",
            "issue_type": "",
            "issue_description": "",
        }

        if not dish_name:
            return with_issues(base_row, [("QUERY_ERROR", "Dish node is missing name/dish_name.")])

        try:
            cypher = build_graph_retrieval_cypher(
                [
                    {
                        "input_name": dish_name,
                        "matched_dish_name": dish_name,
                        "matched_food_id": None,
                        "matched_food_name": None,
                        "retrieval_strategy": "dish_match",
                        "match_score": 100,
                        "match_reason": "exact dish validation",
                    }
                ],
                [],
            )
            graph_rows = self.retriever.retrieve(cypher)
        except Exception as exc:
            return with_issues(base_row, [("QUERY_ERROR", f"{type(exc).__name__}: {exc}")])

        try:
            summaries, debug_rows = self.calculator.summarize_and_recalculate(graph_rows)
            if not summaries:
                return with_issues(base_row, [("AGENT_ERROR", "nutritionist_agent returned no nutrition summary.")])

            summary = summaries[0]
            nutrients = extract_nutrients(summary.nutrients)
            debug = find_debug_row(debug_rows, summary.dish_name)
            protein = nutrients.get("protein_g")
            fat = nutrients.get("fat_g")
            carbohydrate = nutrients.get("carbohydrate_g")
            calculated = calculate_calories(protein, carbohydrate, fat) if all_number(protein, carbohydrate, fat) else None
            calories = exact_graph_calories(graph_rows)

            base_row.update(
                {
                    "calories": round_or_none(calories),
                    "protein_g": round_or_none(protein),
                    "fat_g": round_or_none(fat),
                    "carbohydrate_g": round_or_none(carbohydrate),
                    "sodium_mg": round_or_none(nutrients.get("sodium_mg")),
                    "sugar_g": round_or_none(nutrients.get("sugar_g")),
                    "calculated_calories": round_or_none(calculated),
                    "calorie_difference_percent": calorie_difference_percent(calories, calculated),
                }
            )
            return with_issues(base_row, validate_nutrition_values(base_row))
        except Exception as exc:
            return with_issues(base_row, [("AGENT_ERROR", f"{type(exc).__name__}: {exc}")])


def extract_nutrients(nutrients: Iterable[Any]) -> Dict[str, Optional[float]]:
    extracted: Dict[str, Optional[float]] = {}
    for nutrient in nutrients:
        key = nutrient_key(getattr(nutrient, "name", None), getattr(nutrient, "unit", None))
        if key:
            extracted[key] = getattr(nutrient, "amount_per_serving", None)
    return extracted


def nutrient_key(name: Any, unit: Any) -> Optional[str]:
    raw = str(name or "").strip()
    lowered = raw.lower()
    for key, aliases in NUTRIENT_ALIASES.items():
        if raw in aliases or lowered in aliases:
            return key
    if str(unit or "").lower() == "kcal":
        return "calories"
    return None


def find_debug_row(debug_rows: List[Dict[str, Any]], dish_name: str) -> Dict[str, Any]:
    for row in debug_rows:
        if row.get("dish_name") == dish_name:
            return row
    return debug_rows[0] if debug_rows else {}


def exact_graph_calories(rows: List[Dict[str, Any]]) -> Optional[float]:
    total = 0.0
    found = False
    for row in rows:
        nutrition_name = str(row.get("nutrition_name") or "").strip()
        nutrition_name_zh = str(row.get("nutrition_name_zh") or "").strip()
        if nutrition_name != "熱量" and nutrition_name_zh != "熱量":
            continue
        amount = row.get("amount_per_serving")
        if not is_number(amount):
            continue
        total += float(amount)
        found = True
    return total if found else None


def validate_nutrition_values(row: Dict[str, Any]) -> List[Tuple[str, str]]:
    issues: List[Tuple[str, str]] = []
    dish_name = str(row.get("dish_name") or "")
    major_keys = ("calories", "protein_g", "fat_g", "carbohydrate_g")
    missing = [key for key in major_keys if row.get(key) is None]
    if missing:
        issues.append(("MAJOR_NUTRIENT_MISSING", f"Missing major nutrients: {', '.join(missing)}."))

    numeric_keys = ("calories", "protein_g", "fat_g", "carbohydrate_g", "sodium_mg", "sugar_g")
    negative = [key for key in numeric_keys if is_number(row.get(key)) and float(row[key]) < 0]
    if negative:
        issues.append(("NEGATIVE_VALUE", f"Negative values found: {', '.join(negative)}."))

    threshold_checks = (
        ("CALORIES_TOO_LOW", "calories", lambda value: value < 20, "Calories are below 20 kcal."),
        ("CALORIES_TOO_HIGH", "calories", lambda value: value > 3000, "Calories are above 3000 kcal."),
        ("PROTEIN_TOO_HIGH", "protein_g", lambda value: value > 300, "Protein is above 300 g."),
        ("FAT_TOO_HIGH", "fat_g", lambda value: value > 250, "Fat is above 250 g."),
        ("CARBOHYDRATE_TOO_HIGH", "carbohydrate_g", lambda value: value > 500, "Carbohydrate is above 500 g."),
        ("SODIUM_TOO_HIGH", "sodium_mg", lambda value: value > 10000, "Sodium is above 10000 mg."),
    )
    for issue_type, key, predicate, description in threshold_checks:
        value = row.get(key)
        if is_number(value) and predicate(float(value)):
            issues.append((issue_type, description))

    diff = row.get("calorie_difference_percent")
    if is_number(diff) and float(diff) > 20:
        issues.append(("CALORIE_MISMATCH", "Calories and macro-derived calories differ by more than 20%."))

    calculated = row.get("calculated_calories")
    if is_number(calculated) and float(calculated) < 100 and looks_like_main_meat_rice_or_noodle(dish_name):
        issues.append(
            (
                "LOW_CALCULATED_CALORIES_FOR_MAIN",
                "Calculated calories are below 100 kcal for a dish that looks like a main/meat/rice/noodle item.",
            )
        )
    if is_number(calculated) and float(calculated) > 1200:
        issues.append(("CALCULATED_CALORIES_TOO_HIGH", "Calculated calories are above 1200 kcal."))
    if is_number(row.get("protein_g")) and float(row["protein_g"]) > 80:
        issues.append(("PROTEIN_GT_80", "Protein is above 80 g."))
    if is_number(row.get("fat_g")) and float(row["fat_g"]) > 80:
        issues.append(("FAT_GT_80", "Fat is above 80 g."))
    if is_number(row.get("carbohydrate_g")) and float(row["carbohydrate_g"]) > 150:
        issues.append(("CARBOHYDRATE_GT_150", "Carbohydrate is above 150 g."))
    if is_number(row.get("sodium_mg")) and float(row["sodium_mg"]) > 3000:
        issues.append(("SODIUM_GT_3000", "Sodium is above 3000 mg."))
    if is_number(row.get("sodium_mg")) and float(row["sodium_mg"]) < 50 and looks_like_savory_dish(dish_name):
        issues.append(("SODIUM_LT_50_SAVORY", "Sodium is below 50 mg for a dish that looks savory."))

    return issues


def looks_like_main_meat_rice_or_noodle(dish_name: str) -> bool:
    keywords = (
        "飯",
        "麵",
        "米粉",
        "冬粉",
        "河粉",
        "粥",
        "便當",
        "丼",
        "燴",
        "炒",
        "焗烤",
        "義大利",
        "拉麵",
        "烏龍",
        "鍋",
        "堡",
        "吐司",
        "三明治",
        "蛋餅",
        "雞",
        "豬",
        "牛",
        "羊",
        "魚",
        "蝦",
        "肉",
        "排",
        "腿",
        "排骨",
        "滷",
        "燒",
        "炸",
    )
    return any(keyword in dish_name for keyword in keywords)


def looks_like_savory_dish(dish_name: str) -> bool:
    sweet_or_drink_keywords = (
        "甜",
        "蛋糕",
        "餅乾",
        "布丁",
        "豆花",
        "冰",
        "果汁",
        "奶茶",
        "紅茶",
        "綠茶",
        "咖啡",
        "水果",
        "優格",
        "鬆餅",
        "可可",
    )
    if any(keyword in dish_name for keyword in sweet_or_drink_keywords):
        return False
    savory_keywords = (
        "飯",
        "麵",
        "粥",
        "湯",
        "鍋",
        "堡",
        "吐司",
        "三明治",
        "蛋餅",
        "雞",
        "豬",
        "牛",
        "羊",
        "魚",
        "蝦",
        "肉",
        "排",
        "腿",
        "排骨",
        "滷",
        "燒",
        "炸",
        "炒",
        "燴",
        "焗烤",
        "沙拉",
        "起司",
        "蛋",
        "火腿",
        "培根",
        "熱狗",
        "薯",
    )
    return any(keyword in dish_name for keyword in savory_keywords)


def with_issues(row: Dict[str, Any], issues: List[Tuple[str, str]]) -> Dict[str, Any]:
    if not issues:
        row["validation_status"] = "PASS"
        row["issue_type"] = ""
        row["issue_description"] = ""
        return row

    fail_types = {"QUERY_ERROR", "AGENT_ERROR", "NEGATIVE_VALUE", "MAJOR_NUTRIENT_MISSING"}
    row["validation_status"] = "FAIL" if any(issue_type in fail_types for issue_type, _ in issues) else "WARNING"
    row["issue_type"] = ";".join(issue_type for issue_type, _ in issues)
    row["issue_description"] = " ".join(description for _, description in issues)
    return row


def build_summary_rows(
    *,
    total_dishes: int,
    success_count: int,
    failure_count: int,
    status_counter: Counter[str],
    issue_counter: Counter[str],
) -> List[List[Any]]:
    rows: List[List[Any]] = [
        ["metric", "value"],
        ["總料理數", total_dishes],
        ["成功計算數", success_count],
        ["計算失敗數", failure_count],
        ["PASS 數量", status_counter.get("PASS", 0)],
        ["WARNING 數量", status_counter.get("WARNING", 0)],
        ["FAIL 數量", status_counter.get("FAIL", 0)],
        [],
        ["issue_type", "count"],
    ]
    for issue_type, count in sorted(issue_counter.items()):
        rows.append([issue_type, count])
    return rows


def split_issue_types(value: Any) -> List[str]:
    return [item for item in str(value or "").split(";") if item]


def calorie_difference_percent(calories: Any, calculated: Any) -> Optional[float]:
    if not all_number(calories, calculated) or float(calories) == 0:
        return None
    return round(abs(float(calories) - float(calculated)) / abs(float(calories)) * 100.0, 2)


def all_number(*values: Any) -> bool:
    return all(is_number(value) for value in values)


def is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def round_or_none(value: Any) -> Optional[float]:
    return round(float(value), 2) if is_number(value) else None


def write_ods(path: Path, sheets: Dict[str, List[List[Any]]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w") as ods:
        ods.writestr("mimetype", "application/vnd.oasis.opendocument.spreadsheet", compress_type=zipfile.ZIP_STORED)
        ods.writestr("content.xml", build_content_xml(sheets))
        ods.writestr("styles.xml", build_styles_xml())
        ods.writestr("meta.xml", build_meta_xml())
        ods.writestr("META-INF/manifest.xml", build_manifest_xml())


def build_content_xml(sheets: Dict[str, List[List[Any]]]) -> str:
    tables = "\n".join(build_table_xml(name, rows) for name, rows in sheets.items())
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
  xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
  xmlns:officeooo="http://openoffice.org/2009/office"
  office:version="1.2">
  <office:body>
    <office:spreadsheet>
      {tables}
    </office:spreadsheet>
  </office:body>
</office:document-content>"""


def build_table_xml(name: str, rows: List[List[Any]]) -> str:
    row_xml = "\n".join(build_row_xml(row) for row in rows)
    return f'<table:table table:name="{escape(name)}">\n{row_xml}\n</table:table>'


def build_row_xml(row: List[Any]) -> str:
    cells = "".join(build_cell_xml(value) for value in row)
    return f"<table:table-row>{cells}</table:table-row>"


def build_cell_xml(value: Any) -> str:
    if value is None:
        return "<table:table-cell/>"
    if is_number(value):
        number = float(value)
        return (
            f'<table:table-cell office:value-type="float" office:value="{number}">'
            f"<text:p>{number:g}</text:p></table:table-cell>"
        )
    text = escape(str(value))
    return f'<table:table-cell office:value-type="string"><text:p>{text}</text:p></table:table-cell>'


def build_styles_xml() -> str:
    return """<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  office:version="1.2"/>"""


def build_meta_xml() -> str:
    created = datetime.now().isoformat(timespec="seconds")
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<office:document-meta
  xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
  xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0"
  office:version="1.2">
  <office:meta>
    <meta:generator>nutritionist_agent dish validation</meta:generator>
    <meta:creation-date>{escape(created)}</meta:creation-date>
  </office:meta>
</office:document-meta>"""


def build_manifest_xml() -> str:
    return """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest
  xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
  manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>
</manifest:manifest>"""


if __name__ == "__main__":
    main()
