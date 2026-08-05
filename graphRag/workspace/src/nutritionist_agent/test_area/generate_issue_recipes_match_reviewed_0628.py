from __future__ import annotations

import copy
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional


BASE_DIR = Path(__file__).resolve().parent
WORKSPACE_DIR = BASE_DIR.parents[3]
if str(WORKSPACE_DIR) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_DIR))

from src.nutritionist_agent.test_area.inspect_professional_report import read_xlsx


REPORT_PATH = BASE_DIR / "professional_nutrition_issue_report_v3.xlsx"
SOURCE_RECIPE_PATH = BASE_DIR / "issue_recipes_match_reviewed_v3.json"
NUTRITION_PATH = WORKSPACE_DIR / "data" / "recipe_and_nutrition" / "nutrition_data_categorized.json"
OUTPUT_PATH = BASE_DIR / "issue_recipes_match_reviewed_0628.json"

TARGET_STATUSES = {"FAIL", "WARNING", "WARNNING"}

CORE_RULES = [
    ("叉燒", "叉燒肉", 90),
    ("雞肉", "去皮去骨雞腿(肉雞)", 90),
    ("雞湯", "去皮去骨雞腿(肉雞)", 90),
    ("雞", "去皮去骨雞腿(肉雞)", 90),
    ("牛肉", "牛五花肉火鍋片", 90),
    ("牛", "牛五花肉火鍋片", 90),
    ("豬腸", "豬小腸", 90),
    ("豬", "豬後腿肉", 90),
    ("蝦", "草蝦仁", 80),
    ("干貝", "干貝(冷凍)", 50),
    ("魚", "鯛魚下巴", 100),
    ("蛋", "雞蛋平均值", 55),
]

STAPLE_RULES = [
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

CONDIMENT_CAPS = [
    ("食用鹽", 1.2),
    ("精製食鹽", 1.2),
    ("鹽", 1.2),
    ("醬油", 12),
    ("醬油膏", 10),
    ("豆瓣醬", 10),
    ("麻辣醬", 10),
    ("味噌", 20),
    ("蠔油", 8),
    ("魚露", 4),
    ("米酒", 15),
    ("料理酒", 15),
    ("紹興酒", 15),
]

PORTION_CAPS = [
    (("純植物油", "芝麻油", "香油", "麻油", "紅辣椒油"), 15),
    (("奶油(液態)", "奶油(固態", "鮮奶油"), 45),
    (("乾酪", "起司"), 50),
    (("白飯", "米", "拉麵", "意麵", "乾麵條", "通心麵", "冬粉"), 230),
    (("雞", "牛", "豬", "羊", "魚", "蝦", "肉", "叉燒"), 140),
    (("糖", "砂糖", "紅砂糖", "蜂蜜"), 20),
]

PREFERRED_OVERRIDES = {
    "紅茶茶湯": None,
    "冰水": None,
    "壽司竹簾": None,
    "蘑菇": "洋菇",
    "吉利丁片": "吉利丁片",
    "肉鬆": "豬肉酥",
    "紅糟燒肉片": "叉燒肉",
    "雞蛋": "雞蛋平均值",
    "水煮蛋": "雞水煮蛋",
    "小黃瓜": "花胡瓜(有機)",
    "小黃瓜絲": "花胡瓜(有機)",
    "鮮奶油": "奶油(液態)",
    "蝦仁": "草蝦仁",
    "生粉": "太白粉",
    "豬肉片": "豬後腿肉",
    "雞腿肉": "去皮去骨雞腿(肉雞)",
    "雞胸肉": "里肌肉(肉雞)",
    "雞肉": "去皮去骨雞腿(肉雞)",
    "干貝": "干貝(冷凍)",
}


def main() -> None:
    report_rows = load_target_rows()
    source_recipes = {
        str(recipe.get("recipe_id")): recipe
        for recipe in json.loads(SOURCE_RECIPE_PATH.read_text(encoding="utf-8"))
    }
    foods = FoodCatalog(json.loads(NUTRITION_PATH.read_text(encoding="utf-8")))

    corrected = []
    missing = []
    for row in report_rows:
        recipe_id = str(row.get("recipe_id") or "")
        source = source_recipes.get(recipe_id)
        if not source:
            missing.append(recipe_id)
            continue
        corrected.append(correct_recipe(copy.deepcopy(source), row, foods))

    OUTPUT_PATH.write_text(json.dumps(corrected, ensure_ascii=False, indent=2), encoding="utf-8")
    invalid = validate_ids(corrected, foods)
    print(f"目標 FAIL/WARNING 食譜數: {len(report_rows)}")
    print(f"輸出食譜數: {len(corrected)}")
    print(f"找不到原始食譜數: {len(missing)}")
    print(f"無效整合編號: {len(invalid)}")
    if missing:
        print("missing:", missing[:20])
    if invalid:
        print("invalid:", invalid[:20])
    print(f"輸出位置: {OUTPUT_PATH}")


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
    def __init__(self, nutrition_data: Dict[str, List[Dict[str, Any]]]) -> None:
        self.rows = [row for values in nutrition_data.values() for row in values if isinstance(row, dict)]
        self.valid_ids = {str(row.get("整合編號")) for row in self.rows}
        self.by_name: Dict[str, Dict[str, Any]] = {}
        for row in self.rows:
            for name in names_for_row(row):
                self.by_name.setdefault(normalize(name), row)

    def resolve(self, name: str, current_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
        cleaned = normalize(name)
        override = PREFERRED_OVERRIDES.get(cleaned)
        if override is None and cleaned in PREFERRED_OVERRIDES:
            return None
        if override:
            return self.resolve(override)
        if cleaned in self.by_name:
            return self.by_name[cleaned]
        if current_id and current_id in self.valid_ids:
            return next(row for row in self.rows if str(row.get("整合編號")) == current_id)
        return None


def correct_recipe(recipe: Dict[str, Any], row: Dict[str, Any], foods: FoodCatalog) -> Dict[str, Any]:
    recipe_name = str(recipe.get("recipe_name") or row.get("dish_name") or "")
    issue_type = str(row.get("professional_issue_type") or "")
    description = str(row.get("professional_issue_description") or "")
    ingredients = recipe.get("resolved_ingredients") or []

    apply_preferred_mapping_and_remove(ingredients, foods)

    if "RECIPE_INGREDIENT_SET_MISMATCH" in issue_type:
        ingredients[:] = rebuild_from_name(recipe_name, foods)

    if "MISSING_MAJOR_INGREDIENT" in issue_type or "CALCULATED_CALORIES_TOO_LOW" in issue_type:
        ensure_core_ingredients(ingredients, recipe_name, foods)
        ensure_staple_ingredients(ingredients, recipe_name, foods)

    if "INGREDIENT_MISMATCH_STAPLE" in issue_type:
        ensure_staple_ingredients(ingredients, recipe_name, foods)

    if "PORTION_AMOUNT_HIGH_COOKING_WINE" in issue_type:
        cap_by_keywords(ingredients, [("米酒", 15), ("料理酒", 15), ("紹興酒", 15)])

    if "SODIUM" in issue_type:
        cap_by_keywords(ingredients, CONDIMENT_CAPS)
        if "SODIUM_LOW" in issue_type or "SODIUM_TOO_LOW" in issue_type:
            ensure_salt(ingredients, foods)

    if any(token in issue_type for token in ("CALCULATED_CALORIES_HIGH", "FAT_HIGH", "PROTEIN_HIGH", "CARB_HIGH", "PORTION")):
        cap_by_keyword_groups(ingredients, PORTION_CAPS)

    finalize_ingredients(ingredients, foods)
    recipe["recipe_id"] = recipe.get("recipe_id")
    recipe["recipe_name"] = recipe.get("recipe_name") or recipe_name
    recipe["resolved_ingredients"] = ingredients
    recipe["servings"] = "1"
    return recipe


def rebuild_from_name(recipe_name: str, foods: FoodCatalog) -> List[Dict[str, Any]]:
    ingredients: List[Dict[str, Any]] = []
    ensure_staple_ingredients(ingredients, recipe_name, foods)
    ensure_core_ingredients(ingredients, recipe_name, foods)
    if not ingredients:
        ensure_core_ingredients(ingredients, recipe_name + "豬", foods)
        ensure_staple_ingredients(ingredients, recipe_name + "飯", foods)
    if any(keyword in recipe_name for keyword in ("盒", "飯", "便當")):
        add_if_missing(ingredients, "白飯", "白飯", 220, foods)
    add_if_missing(ingredients, "醬油", "醬油", 10, foods)
    add_if_missing(ingredients, "鹽", "食用鹽", 1, foods)
    add_if_missing(ingredients, "純植物油", "純植物油", 8, foods)
    return ingredients


def ensure_core_ingredients(ingredients: List[Dict[str, Any]], recipe_name: str, foods: FoodCatalog) -> None:
    names = joined_names(ingredients)
    for keyword, food_name, amount in CORE_RULES:
        if keyword in recipe_name and keyword not in names and normalize(food_name) not in normalize(names):
            add_if_missing(ingredients, keyword, food_name, amount, foods)


def ensure_staple_ingredients(ingredients: List[Dict[str, Any]], recipe_name: str, foods: FoodCatalog) -> None:
    names = joined_names(ingredients)
    for keyword, food_name, amount in STAPLE_RULES:
        if keyword in recipe_name and keyword not in names and normalize(food_name) not in normalize(names):
            add_if_missing(ingredients, keyword, food_name, amount, foods)


def ensure_salt(ingredients: List[Dict[str, Any]], foods: FoodCatalog) -> None:
    if "鹽" not in joined_names(ingredients):
        add_if_missing(ingredients, "鹽", "食用鹽", 1, foods)


def apply_preferred_mapping_and_remove(ingredients: List[Dict[str, Any]], foods: FoodCatalog) -> None:
    kept = []
    for ingredient in ingredients:
        original = str(ingredient.get("original") or "")
        matched = str(ingredient.get("matched") or original)
        override = PREFERRED_OVERRIDES.get(normalize(original))
        if override is None and normalize(original) in PREFERRED_OVERRIDES:
            continue
        food = foods.resolve(original) if override else None
        food = food or foods.resolve(matched, str(ingredient.get("整合編號") or ""))
        if food:
            set_food(ingredient, food)
        kept.append(ingredient)
    ingredients[:] = kept


def cap_by_keywords(ingredients: List[Dict[str, Any]], caps: List[tuple[str, float]]) -> None:
    for ingredient in ingredients:
        name = str(ingredient.get("matched") or ingredient.get("original") or "")
        amount = as_float(ingredient.get("amount_per_serving"))
        if amount is None:
            continue
        for keyword, cap in caps:
            if keyword in name and amount > cap:
                set_amount(ingredient, cap)


def cap_by_keyword_groups(ingredients: List[Dict[str, Any]], caps: List[tuple[tuple[str, ...], float]]) -> None:
    for ingredient in ingredients:
        name = str(ingredient.get("matched") or ingredient.get("original") or "")
        amount = as_float(ingredient.get("amount_per_serving"))
        if amount is None:
            continue
        for keywords, cap in caps:
            if any(keyword in name for keyword in keywords) and amount > cap:
                set_amount(ingredient, cap)
                break


def finalize_ingredients(ingredients: List[Dict[str, Any]], foods: FoodCatalog) -> None:
    for ingredient in ingredients:
        food = foods.resolve(str(ingredient.get("matched") or ingredient.get("original") or ""), str(ingredient.get("整合編號") or ""))
        if food:
            set_food(ingredient, food)
        amount = as_float(ingredient.get("amount_per_serving"))
        if amount is not None:
            set_amount(ingredient, amount)
        ingredient.setdefault("amount_note", None)


def add_if_missing(ingredients: List[Dict[str, Any]], original: str, matched: str, amount: float, foods: FoodCatalog) -> None:
    if normalize(original) in normalize(joined_names(ingredients)) or normalize(matched) in normalize(joined_names(ingredients)):
        return
    food = foods.resolve(matched)
    if not food:
        return
    ingredients.append(
        {
            "original": original,
            "matched": food["樣品名稱"],
            "整合編號": food["整合編號"],
            "method": "Professional v3 issue correction",
            "amount_raw": f"{format_amount(amount)}g",
            "amount_value": amount,
            "amount_unit": "g",
            "amount_note": None,
            "amount_per_serving": amount,
        }
    )


def set_food(ingredient: Dict[str, Any], food: Dict[str, Any]) -> None:
    ingredient["matched"] = food["樣品名稱"]
    ingredient["整合編號"] = food["整合編號"]
    ingredient["method"] = "Professional v3 issue correction"


def set_amount(ingredient: Dict[str, Any], amount: float) -> None:
    amount = round(float(amount), 2)
    unit = str(ingredient.get("amount_unit") or "g")
    if unit in {"克", "公克"}:
        unit = "g"
    ingredient["amount_per_serving"] = amount
    ingredient["amount_value"] = amount
    ingredient["amount_unit"] = unit
    ingredient["amount_raw"] = f"{format_amount(amount)}{unit}"


def validate_ids(recipes: List[Dict[str, Any]], foods: FoodCatalog) -> List[tuple[str, str, str]]:
    invalid = []
    for recipe in recipes:
        for ingredient in recipe.get("resolved_ingredients", []):
            food_id = str(ingredient.get("整合編號"))
            if food_id not in foods.valid_ids:
                invalid.append((recipe.get("recipe_id"), ingredient.get("matched"), food_id))
    return invalid


def names_for_row(row: Dict[str, Any]) -> List[str]:
    names = [str(row.get("樣品名稱") or "")]
    alias = row.get("俗名")
    if alias:
        names.extend(re.split(r"[,、/，；;]", str(alias)))
    return [name.strip() for name in names if name and name.strip()]


def joined_names(ingredients: List[Dict[str, Any]]) -> str:
    return " ".join(str(item.get("original", "")) + " " + str(item.get("matched", "")) for item in ingredients)


def normalize(value: str) -> str:
    return re.sub(r"\s+", "", str(value or "").strip())


def as_float(value: Any) -> Optional[float]:
    try:
        if value in (None, ""):
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def format_amount(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else str(round(value, 2))


if __name__ == "__main__":
    main()
