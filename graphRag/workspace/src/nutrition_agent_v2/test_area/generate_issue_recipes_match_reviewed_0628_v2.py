from __future__ import annotations

import copy
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


BASE_DIR = Path(__file__).resolve().parent
WORKSPACE_DIR = BASE_DIR.parents[2]
OUTPUT_DIR = BASE_DIR / "output"
if str(WORKSPACE_DIR) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_DIR))

from src.nutrition_agent_v2.test_area.inspect_professional_report import read_xlsx


REPORT_PATH = OUTPUT_DIR / "professional_nutrition_issue_report_v3.xlsx"
SOURCE_RECIPE_PATH = OUTPUT_DIR / "issue_recipes_match_reviewed_v3.json"
NUTRITION_PATH = WORKSPACE_DIR / "data" / "recipe_and_nutrition" / "nutrition_data_categorized.json"
OUTPUT_PATH = OUTPUT_DIR / "issue_recipes_match_reviewed_0628.json"
MISSING_PATH = OUTPUT_DIR / "missing_needed_ingredients_0628.json"

TARGET_STATUSES = {"FAIL", "WARNING", "WARNNING"}

PREFERRED_MATCH = {
    "奶油": "奶油(固態,不加鹽)",
    "無鹽奶油": "奶油(固態,不加鹽)",
    "鮮奶油": "奶油(液態)",
    "年糕": "年糕",
    "豬腸": "豬小腸",
    "豬大腸": "豬大腸",
    "豬小腸": "豬小腸",
    "雞肉": "去皮去骨雞腿(肉雞)",
    "雞腿肉": "去皮去骨雞腿(肉雞)",
    "雞胸肉": "里肌肉(肉雞)",
    "雞蛋": "雞蛋平均值",
    "水煮蛋": "雞水煮蛋",
    "叉燒": "叉燒肉",
    "紅糟燒肉片": "叉燒肉",
    "牛肉": "牛五花肉火鍋片",
    "蘑菇": "洋菇",
    "吉利丁片": "吉利丁片",
    "蝦仁": "草蝦仁",
    "干貝": "干貝(冷凍)",
    "小黃瓜": "花胡瓜(有機)",
    "小黃瓜絲": "花胡瓜(有機)",
    "生粉": "太白粉",
    "壽司竹簾": None,
    "紅茶茶湯": None,
    "冰水": None,
}

CORE_BY_NAME = [
    ("年糕", "年糕", 120),
    ("豬腸", "豬小腸", 90),
    ("叉燒", "叉燒肉", 90),
    ("雞肉", "去皮去骨雞腿(肉雞)", 90),
    ("雞湯", "去皮去骨雞腿(肉雞)", 90),
    ("雞", "去皮去骨雞腿(肉雞)", 90),
    ("牛肉", "牛五花肉火鍋片", 90),
    ("牛", "牛五花肉火鍋片", 90),
    ("蝦", "草蝦仁", 80),
    ("干貝", "干貝(冷凍)", 50),
    ("蛋", "雞蛋平均值", 55),
]

STAPLE_BY_NAME = [
    ("拉麵", "拉麵", 180),
    ("意麵", "意麵", 180),
    ("冬粉", "冬粉", 120),
    ("義大利", "通心麵", 180),
    ("麵", "乾麵條", 170),
    ("飯", "白飯", 220),
    ("丼", "白飯", 220),
    ("燉飯", "白飯", 220),
    ("粥", "白飯", 160),
    ("吐司", "土司", 60),
    ("蛋餅", "蛋餅皮", 55),
    ("漢堡", "漢堡麵包", 65),
]

CAPS = [
    (("奶油(液態)", "奶油(固態", "鮮奶油"), 45),
    (("食用鹽", "精製食鹽", "鹽"), 1.2),
    (("醬油",), 12),
    (("醬油膏",), 10),
    (("豆瓣醬", "麻辣醬", "蠔油"), 10),
    (("魚露",), 4),
    (("味噌",), 20),
    (("米酒", "料理酒", "紹興酒"), 15),
    (("純植物油", "芝麻油", "香油", "麻油", "紅辣椒油"), 15),
    (("白飯", "米", "拉麵", "意麵", "乾麵條", "通心麵", "冬粉", "年糕"), 230),
    (("雞", "牛", "豬", "羊", "魚", "蝦", "肉", "叉燒", "豬小腸", "豬大腸"), 140),
    (("糖", "砂糖", "紅砂糖", "蜂蜜"), 20),
]

MISSING: Dict[str, Dict[str, Any]] = {}


def main() -> None:
    foods = FoodCatalog(json.loads(NUTRITION_PATH.read_text(encoding="utf-8")))
    source = {str(item.get("recipe_id")): item for item in json.loads(SOURCE_RECIPE_PATH.read_text(encoding="utf-8"))}
    targets = load_target_rows()

    output = []
    missing_source = []
    for row in targets:
        recipe_id = str(row.get("recipe_id") or "")
        recipe = source.get(recipe_id)
        if not recipe:
            missing_source.append(recipe_id)
            continue
        output.append(correct_recipe(copy.deepcopy(recipe), row, foods))

    OUTPUT_PATH.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    MISSING_PATH.write_text(json.dumps(list(MISSING.values()), ensure_ascii=False, indent=2), encoding="utf-8")

    invalid = validate_ids(output, foods)
    print(f"目標 FAIL/WARNING 食譜數: {len(targets)}")
    print(f"輸出食譜數: {len(output)}")
    print(f"找不到原始食譜數: {len(missing_source)}")
    print(f"無效整合編號: {len(invalid)}")
    print(f"需要但資料表不存在食材數: {len(MISSING)}")
    if missing_source:
        print("missing_source:", missing_source[:20])
    if invalid:
        print("invalid:", invalid[:20])
    print(f"輸出位置: {OUTPUT_PATH}")
    print(f"缺失食材清單: {MISSING_PATH}")


def load_target_rows() -> List[Dict[str, Any]]:
    workbook = read_xlsx(REPORT_PATH)
    rows = workbook["FinalIssues"]
    header_index = next(index for index, row in enumerate(rows) if row and row[0] == "recipe_id")
    headers = [str(item) for item in rows[header_index]]
    result = []
    for raw in rows[header_index + 1 :]:
        if not raw:
            continue
        item = {header: raw[index] if index < len(raw) else "" for index, header in enumerate(headers)}
        if str(item.get("professional_status") or "").strip().upper() in TARGET_STATUSES:
            result.append(item)
    return result


class FoodCatalog:
    def __init__(self, data: Dict[str, List[Dict[str, Any]]]) -> None:
        self.rows = [row for values in data.values() for row in values if isinstance(row, dict)]
        self.valid_ids = {str(row.get("整合編號")) for row in self.rows}
        self.by_name: Dict[str, Dict[str, Any]] = {}
        for row in self.rows:
            for name in names_for(row):
                self.by_name.setdefault(normalize(name), row)

    def resolve(self, name: str, current_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
        key = normalize(name)
        if key in {normalize(k) for k, v in PREFERRED_MATCH.items() if v is None}:
            return None
        override = find_override(name)
        if override and normalize(override) != key:
            return self.resolve(override)
        if key in self.by_name:
            return self.by_name[key]
        if current_id and current_id in self.valid_ids:
            return next(row for row in self.rows if str(row.get("整合編號")) == current_id)
        return None


def correct_recipe(recipe: Dict[str, Any], row: Dict[str, Any], foods: FoodCatalog) -> Dict[str, Any]:
    recipe_name = str(recipe.get("recipe_name") or row.get("dish_name") or "")
    issue_type = str(row.get("professional_issue_type") or "")
    desc = str(row.get("professional_issue_description") or "")
    ingredients = recipe.get("resolved_ingredients") or []

    apply_overrides_and_remove(ingredients, foods)

    if should_rebuild_whole_recipe(recipe_name, issue_type, desc):
        ingredients[:] = rebuild_recipe(recipe.get("recipe_id"), recipe_name, foods)
    else:
        fix_explicit_description_issues(ingredients, recipe.get("recipe_id"), recipe_name, desc, foods)
        if any(token in issue_type for token in ("MISSING_MAJOR_INGREDIENT", "MISSING_STAPLE", "CALCULATED_CALORIES_LOW", "CALCULATED_CALORIES_TOO_LOW")):
            ensure_name_based_ingredients(ingredients, recipe.get("recipe_id"), recipe_name, foods)

    if "SODIUM" in issue_type:
        cap_amounts(ingredients, CAPS)
        if "LOW" in issue_type or "SUSPICIOUSLY_LOW" in issue_type:
            add_needed(ingredients, recipe.get("recipe_id"), recipe_name, "鹽", "食用鹽", 1, foods)

    if any(token in issue_type for token in ("HIGH", "EXTREME", "PORTION_AMOUNT")):
        cap_amounts(ingredients, CAPS)

    finalize(ingredients, foods)
    recipe["recipe_id"] = recipe.get("recipe_id")
    recipe["recipe_name"] = recipe.get("recipe_name") or recipe_name
    recipe["resolved_ingredients"] = ingredients
    recipe["servings"] = "1"
    return recipe


def should_rebuild_whole_recipe(recipe_name: str, issue_type: str, desc: str) -> bool:
    if "玉米濃湯" in recipe_name and ("奶油錯配" in desc or "SODIUM" in issue_type):
        return True
    if "RECIPE_INGREDIENT_SET_MISMATCH" in issue_type:
        return True
    return False


def rebuild_recipe(recipe_id: Any, recipe_name: str, foods: FoodCatalog) -> List[Dict[str, Any]]:
    if "玉米濃湯" in recipe_name:
        specs = [
            ("甜玉米", "甜玉米", 90),
            ("鮮奶", "鮮乳(平均值)", 160),
            ("奶油", "奶油(固態,不加鹽)", 8),
            ("雞蛋", "雞蛋平均值", 45),
            ("玉米粉", "玉米粉", 6),
            ("水", "純水", 180),
            ("鹽", "食用鹽", 0.6),
            ("黑胡椒粉", "黑胡椒粉", 0.5),
        ]
    else:
        specs = []
        for keyword, food, amount in STAPLE_BY_NAME + CORE_BY_NAME:
            if keyword in recipe_name:
                specs.append((keyword, food, amount))
        if any(k in recipe_name for k in ("盒", "飯", "便當")):
            specs.append(("白飯", "白飯", 220))
        specs.extend([("醬油", "醬油", 10), ("鹽", "食用鹽", 1), ("油", "純植物油", 8)])
    result: List[Dict[str, Any]] = []
    for original, matched, amount in specs:
        add_needed(result, recipe_id, recipe_name, original, matched, amount, foods)
    return result


def fix_explicit_description_issues(
    ingredients: List[Dict[str, Any]],
    recipe_id: Any,
    recipe_name: str,
    desc: str,
    foods: FoodCatalog,
) -> None:
    explicit_rules = [
        ("年糕", "年糕", 120),
        ("叉燒", "叉燒肉", 90),
        ("雞肉/雞湯", "去皮去骨雞腿(肉雞)", 90),
        ("雞肉", "去皮去骨雞腿(肉雞)", 90),
        ("豬腸", "豬小腸", 90),
        ("牛肉", "牛五花肉火鍋片", 90),
    ]
    for marker, food, amount in explicit_rules:
        if marker in desc or marker in recipe_name:
            add_needed(ingredients, recipe_id, recipe_name, marker.replace("/雞湯", ""), food, amount, foods)

    for original, _wrong in re.findall(r"([^：；，,]+?)→([^；，,]+)", desc):
        original = original.strip()
        override = find_override(original)
        if not override:
            continue
        for ing in ingredients:
            if original in str(ing.get("original") or ""):
                food = foods.resolve(override)
                if food:
                    set_food(ing, food)


def ensure_name_based_ingredients(ingredients: List[Dict[str, Any]], recipe_id: Any, recipe_name: str, foods: FoodCatalog) -> None:
    for keyword, food, amount in STAPLE_BY_NAME + CORE_BY_NAME:
        if keyword in recipe_name:
            add_needed(ingredients, recipe_id, recipe_name, keyword, food, amount, foods)


def apply_overrides_and_remove(ingredients: List[Dict[str, Any]], foods: FoodCatalog) -> None:
    kept = []
    for ing in ingredients:
        original = str(ing.get("original") or "")
        matched = str(ing.get("matched") or original)
        if find_override(original) is None and normalize(original) in {normalize(k) for k, v in PREFERRED_MATCH.items() if v is None}:
            continue
        food = foods.resolve(original) if find_override(original) else None
        food = food or foods.resolve(matched, str(ing.get("整合編號") or ""))
        if food:
            set_food(ing, food)
        kept.append(ing)
    ingredients[:] = kept


def add_needed(
    ingredients: List[Dict[str, Any]],
    recipe_id: Any,
    recipe_name: str,
    original: str,
    matched: str,
    amount: float,
    foods: FoodCatalog,
) -> None:
    existing_names = {
        normalize(value)
        for ing in ingredients
        for value in (ing.get("original"), ing.get("matched"))
        if value
    }
    if normalize(original) in existing_names or normalize(matched) in existing_names:
        return
    food = foods.resolve(matched)
    if not food:
        remember_missing(recipe_id, recipe_name, original, matched)
        return
    ingredients.append(
        {
            "original": original,
            "matched": food["樣品名稱"],
            "整合編號": food["整合編號"],
            "method": "Professional v3 issue correction 0628",
            "amount_raw": f"{fmt(amount)}g",
            "amount_value": amount,
            "amount_unit": "g",
            "amount_note": None,
            "amount_per_serving": amount,
        }
    )


def cap_amounts(ingredients: List[Dict[str, Any]], caps: List[tuple[tuple[str, ...], float]]) -> None:
    for ing in ingredients:
        name = str(ing.get("matched") or ing.get("original") or "")
        amount = as_float(ing.get("amount_per_serving"))
        if amount is None:
            continue
        for keywords, cap in caps:
            if any(k in name for k in keywords):
                if amount > cap:
                    set_amount(ing, cap)
                break


def finalize(ingredients: List[Dict[str, Any]], foods: FoodCatalog) -> None:
    for ing in ingredients:
        food = foods.resolve(str(ing.get("matched") or ing.get("original") or ""), str(ing.get("整合編號") or ""))
        if food:
            set_food(ing, food)
        amount = as_float(ing.get("amount_per_serving"))
        if amount is not None:
            set_amount(ing, amount)
        ing.setdefault("amount_note", None)


def set_food(ing: Dict[str, Any], food: Dict[str, Any]) -> None:
    ing["matched"] = food["樣品名稱"]
    ing["整合編號"] = food["整合編號"]
    ing["method"] = "Professional v3 issue correction 0628"
    note = str(ing.get("amount_note") or "")
    if "麵筋" in note or "錯配" in note or "取代" in note:
        ing["amount_note"] = None


def set_amount(ing: Dict[str, Any], amount: float) -> None:
    amount = round(float(amount), 2)
    unit = str(ing.get("amount_unit") or "g")
    if unit in {"克", "公克"}:
        unit = "g"
    ing["amount_per_serving"] = amount
    ing["amount_value"] = amount
    ing["amount_unit"] = unit
    ing["amount_raw"] = f"{fmt(amount)}{unit}"


def remember_missing(recipe_id: Any, recipe_name: str, original: str, intended: str) -> None:
    key = f"{original}|{intended}"
    row = MISSING.setdefault(
        key,
        {"needed_ingredient": original, "intended_match": intended, "recipes": []},
    )
    row["recipes"].append({"recipe_id": recipe_id, "recipe_name": recipe_name})


def find_override(name: str) -> Optional[str]:
    key = normalize(name)
    for original, target in PREFERRED_MATCH.items():
        if normalize(original) == key:
            return target
    return None


def names_for(row: Dict[str, Any]) -> List[str]:
    names = [str(row.get("樣品名稱") or "")]
    alias = row.get("俗名")
    if alias:
        names.extend(re.split(r"[,、/，；;]", str(alias)))
    return [x.strip() for x in names if x and x.strip()]


def validate_ids(recipes: List[Dict[str, Any]], foods: FoodCatalog) -> List[tuple[str, str, str]]:
    bad = []
    for recipe in recipes:
        for ing in recipe.get("resolved_ingredients", []):
            if str(ing.get("整合編號")) not in foods.valid_ids:
                bad.append((recipe.get("recipe_id"), ing.get("matched"), ing.get("整合編號")))
    return bad


def normalize(value: str) -> str:
    return re.sub(r"\s+", "", str(value or "").strip())


def as_float(value: Any) -> Optional[float]:
    try:
        if value in (None, ""):
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def fmt(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else str(round(value, 2))


if __name__ == "__main__":
    main()
