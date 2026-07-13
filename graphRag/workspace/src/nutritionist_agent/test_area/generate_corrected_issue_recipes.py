from __future__ import annotations

import copy
import json
import re
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

from .inspect_professional_report import XLSX_PATH, read_xlsx


BASE_DIR = Path(__file__).resolve().parent
WORKSPACE_DIR = BASE_DIR.parents[2]
ISSUE_RECIPE_PATH = BASE_DIR / "issue_recipe_details_from_validation_report.json"
NUTRITION_PATH = WORKSPACE_DIR / "data" / "recipe_and_nutrition" / "nutrition_data_categorized.json"
OUTPUT_PATH = BASE_DIR / "corrected_issue_recipes_from_professional_report.json"

TARGET_STATUSES = {"FAIL", "WARNING", "WARNNING"}
NON_FOOD_KEYWORDS = ("竹簾", "餐盒", "盒", "包裝", "吸管", "杯", "碗", "盤")

SAVORY_KEYWORDS = (
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
)

MAIN_FOOD_RULES = [
    ("拉麵", "拉麵", 180),
    ("意麵", "意麵", 180),
    ("義大利", "通心麵", 180),
    ("麵", "麵條", 170),
    ("冬粉", "冬粉", 120),
    ("飯", "白飯", 220),
    ("丼", "白飯", 220),
    ("燉飯", "白飯", 220),
    ("粥", "白飯", 160),
    ("吐司", "土司", 60),
    ("三明治", "土司", 60),
    ("漢堡", "漢堡麵包", 65),
    ("蛋餅", "蛋餅皮", 55),
    ("雞", "去皮去骨雞腿", 100),
    ("牛", "牛五花肉火鍋片", 90),
    ("豬", "豬肉平均值", 90),
    ("蝦", "草蝦仁", 80),
    ("魚", "魚片平均值", 90),
]

CONDIMENT_RULES = [
    ("醬油", 10),
    ("醬油膏", 8),
    ("精製食鹽", 1),
    ("鹽", 1),
    ("麻辣醬", 8),
    ("豆瓣醬", 8),
    ("味噌", 12),
    ("沙茶醬", 10),
    ("蠔油", 8),
    ("魚露", 4),
]

SPECIAL_FOOD_NAMES = {
    "鮭魚頭": "大西洋鮭魚切片(中段)",
    "鮭魚下巴": "大西洋鮭魚腹肉",
    "䱽魚": "鯛魚下巴",
    "生粉": "太白粉",
    "鮮奶油": "奶油(液態)",
    "蝦仁": "草蝦仁",
}


def main() -> None:
    foods = FoodResolver(load_food_rows())
    professional_rows = load_professional_rows()
    issue_recipes = {
        str(recipe.get("recipe_id")): recipe
        for recipe in json.loads(ISSUE_RECIPE_PATH.read_text(encoding="utf-8"))
    }

    corrected: List[Dict[str, Any]] = []
    missing_ids: List[str] = []
    for row in professional_rows:
        recipe_id = str(row.get("recipe_id") or "").strip()
        recipe = issue_recipes.get(recipe_id)
        if not recipe:
            missing_ids.append(recipe_id)
            continue
        corrected.append(correct_recipe(copy.deepcopy(recipe), row, foods))

    OUTPUT_PATH.write_text(json.dumps(corrected, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"需修正食譜數: {len(professional_rows)}")
    print(f"輸出食譜數: {len(corrected)}")
    print(f"找不到原始食譜數: {len(missing_ids)}")
    if missing_ids:
        print("missing_recipe_ids:", ", ".join(missing_ids[:30]))
    print(f"輸出位置: {OUTPUT_PATH}")


def load_professional_rows() -> List[Dict[str, Any]]:
    workbook = read_xlsx(XLSX_PATH)
    rows = workbook["IssueReport_All"]
    headers = [str(item) for item in rows[0]]
    data = []
    for raw in rows[1:]:
        item = {header: raw[index] if index < len(raw) else "" for index, header in enumerate(headers)}
        if str(item.get("corrected_status") or "").strip().upper() in TARGET_STATUSES:
            data.append(item)
    return data


def load_food_rows() -> List[Dict[str, Any]]:
    data = json.loads(NUTRITION_PATH.read_text(encoding="utf-8"))
    return [row for rows in data.values() for row in rows if isinstance(row, dict)]


class FoodResolver:
    def __init__(self, rows: List[Dict[str, Any]]) -> None:
        self.rows = rows
        self.by_id = {str(row.get("整合編號")): row for row in rows if row.get("整合編號")}
        self.by_name: Dict[str, Dict[str, Any]] = {}
        for row in rows:
            for key in ("樣品名稱", "俗名"):
                value = row.get(key)
                if not value:
                    continue
                for name in str(value).replace("、", ",").split(","):
                    cleaned = normalize_name(name)
                    if cleaned and cleaned not in self.by_name:
                        self.by_name[cleaned] = row

    def resolve(self, name: str, current_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
        cleaned = normalize_name(name)
        special = SPECIAL_FOOD_NAMES.get(cleaned)
        if special and normalize_name(special) != cleaned:
            return self.resolve(special)
        if cleaned in self.by_name:
            return self.by_name[cleaned]
        if current_id and current_id in self.by_id:
            return self.by_id[current_id]
        for candidate, row in self.by_name.items():
            if cleaned and (cleaned in candidate or candidate in cleaned):
                return row
        return None


def correct_recipe(recipe: Dict[str, Any], row: Dict[str, Any], foods: FoodResolver) -> Dict[str, Any]:
    recipe_name = str(recipe.get("recipe_name") or row.get("dish_name") or "")
    issue_type = str(row.get("corrected_issue_type") or "")
    reason = str(row.get("professional_reason") or "")
    action = str(row.get("suggested_action") or "")
    summary = str(row.get("ingredient_summary") or "")

    ingredients = recipe.get("resolved_ingredients") or []
    remove_non_foods(ingredients, reason)
    apply_mapping_suggestions(ingredients, summary + "；" + reason, foods)

    if "PORTION_TOO_LARGE" in issue_type or "MACRO_EXTREME" in issue_type:
        normalize_large_portions(ingredients, recipe_name)
    if "PORTION_TOO_SMALL" in issue_type:
        normalize_small_portions(ingredients, recipe_name)
    if "SODIUM_EXTREME" in issue_type or "SODIUM_TOO_HIGH" in issue_type or "SODIUM_REVIEW" in issue_type:
        normalize_sodium_sources(ingredients)
    if "SODIUM_TOO_LOW" in issue_type:
        ensure_savory_sodium(ingredients, recipe_name, foods)
    if "MISSING_KEY_INGREDIENT" in issue_type or "PORTION_TOO_SMALL_OR_MISSING_INGREDIENT" in issue_type:
        ensure_main_ingredients(ingredients, recipe_name, foods)

    finalize_ingredients(ingredients, foods)
    recipe["recipe_name"] = recipe.get("recipe_name") or recipe_name
    recipe["resolved_ingredients"] = ingredients
    recipe["servings"] = "1"
    return recipe


def remove_non_foods(ingredients: List[Dict[str, Any]], reason: str) -> None:
    explicit = re.findall(r"非食材被納入[:：]([^；。,\s]+)", reason)
    def should_remove(ingredient: Dict[str, Any]) -> bool:
        names = f"{ingredient.get('original', '')} {ingredient.get('matched', '')}"
        return any(item and item in names for item in explicit) or any(keyword in names for keyword in NON_FOOD_KEYWORDS)
    ingredients[:] = [ingredient for ingredient in ingredients if not should_remove(ingredient)]


def apply_mapping_suggestions(ingredients: List[Dict[str, Any]], text: str, foods: FoodResolver) -> None:
    for original, matched in re.findall(r"([^；，。、:：\s()]+?)→([^；，。、()]+)", text):
        matched = matched.strip()
        food = foods.resolve(matched)
        if not food:
            continue
        for ingredient in ingredients:
            names = f"{ingredient.get('original', '')} {ingredient.get('matched', '')}"
            if original.strip() in names:
                set_food(ingredient, original.strip(), food)


def normalize_large_portions(ingredients: List[Dict[str, Any]], recipe_name: str) -> None:
    target_caps = [
        (("油", "奶油", "麻油", "香油"), 15),
        (("糖", "砂糖", "蜂蜜"), 20),
        (("飯", "米", "麵", "冬粉", "通心麵", "拉麵", "意麵"), 220),
        (("牛", "豬", "雞", "羊", "蝦", "魚", "肉", "排"), 130),
        (("起司", "乾酪", "鮮奶油"), 50),
        (("醬", "醬油", "豆瓣", "麻辣"), 20),
    ]
    for ingredient in ingredients:
        name = f"{ingredient.get('original', '')}{ingredient.get('matched', '')}"
        amount = as_float(ingredient.get("amount_per_serving"))
        if amount is None:
            continue
        for keywords, cap in target_caps:
            if any(keyword in name for keyword in keywords) and amount > cap:
                set_amount(ingredient, cap)
                break


def normalize_small_portions(ingredients: List[Dict[str, Any]], recipe_name: str) -> None:
    minimums = [
        (("魚", "鮭", "鯛", "鱈"), 120),
        (("雞", "牛", "豬", "羊", "蝦", "肉", "排"), 90),
        (("飯", "米"), 180),
        (("麵", "冬粉", "通心麵", "拉麵", "意麵"), 140),
    ]
    for ingredient in ingredients:
        name = f"{ingredient.get('original', '')}{ingredient.get('matched', '')}"
        amount = as_float(ingredient.get("amount_per_serving"))
        if amount is None:
            continue
        for keywords, minimum in minimums:
            if any(keyword in name for keyword in keywords) and amount < minimum:
                set_amount(ingredient, minimum)
                break


def normalize_sodium_sources(ingredients: List[Dict[str, Any]]) -> None:
    for ingredient in ingredients:
        matched = str(ingredient.get("matched") or ingredient.get("original") or "")
        for keyword, cap in CONDIMENT_RULES:
            if keyword in matched:
                amount = as_float(ingredient.get("amount_per_serving"))
                if amount is not None and amount > cap:
                    set_amount(ingredient, cap)


def ensure_savory_sodium(ingredients: List[Dict[str, Any]], recipe_name: str, foods: FoodResolver) -> None:
    if not any(keyword in recipe_name for keyword in SAVORY_KEYWORDS):
        return
    if any("鹽" in str(item.get("matched") or item.get("original") or "") for item in ingredients):
        return
    add_ingredient(ingredients, "鹽", "精製食鹽", 1, foods)


def ensure_main_ingredients(ingredients: List[Dict[str, Any]], recipe_name: str, foods: FoodResolver) -> None:
    names = "".join(str(item.get("original", "")) + str(item.get("matched", "")) for item in ingredients)
    for keyword, food_name, amount in MAIN_FOOD_RULES:
        if keyword in recipe_name and keyword not in names and food_name not in names:
            add_ingredient(ingredients, food_name, food_name, amount, foods)


def finalize_ingredients(ingredients: List[Dict[str, Any]], foods: FoodResolver) -> None:
    for ingredient in ingredients:
        original = str(ingredient.get("original") or "")
        matched = str(ingredient.get("matched") or original)
        food = foods.resolve(original) if normalize_name(original) in SPECIAL_FOOD_NAMES else None
        food = food or foods.resolve(matched, str(ingredient.get("整合編號") or ""))
        if food:
            set_food(ingredient, str(ingredient.get("original") or food.get("樣品名稱")), food)
        if ingredient.get("amount_note") == "":
            ingredient["amount_note"] = None
        amount = as_float(ingredient.get("amount_per_serving"))
        if amount is not None:
            set_amount(ingredient, amount)


def add_ingredient(
    ingredients: List[Dict[str, Any]],
    original: str,
    matched_name: str,
    amount: float,
    foods: FoodResolver,
) -> None:
    food = foods.resolve(matched_name)
    if not food:
        return
    ingredient = {
        "original": original,
        "matched": food["樣品名稱"],
        "整合編號": food["整合編號"],
        "method": "Professional issue correction",
        "amount_raw": f"{format_amount(amount)}g",
        "amount_value": amount,
        "amount_unit": "g",
        "amount_note": None,
        "amount_per_serving": amount,
    }
    ingredients.append(ingredient)


def set_food(ingredient: Dict[str, Any], original_hint: str, food: Dict[str, Any]) -> None:
    ingredient["original"] = ingredient.get("original") or original_hint
    ingredient["matched"] = food["樣品名稱"]
    ingredient["整合編號"] = food["整合編號"]
    ingredient["method"] = "Professional issue correction"


def set_amount(ingredient: Dict[str, Any], amount: float) -> None:
    rounded = round(float(amount), 2)
    ingredient["amount_per_serving"] = rounded
    ingredient["amount_value"] = rounded
    unit = str(ingredient.get("amount_unit") or "g")
    if unit in {"克", "公克"}:
        unit = "g"
    ingredient["amount_unit"] = unit
    ingredient["amount_raw"] = f"{format_amount(rounded)}{unit}"


def normalize_name(name: str) -> str:
    return re.sub(r"\s+", "", str(name or "").strip())


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
