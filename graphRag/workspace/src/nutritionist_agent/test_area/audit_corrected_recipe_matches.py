from __future__ import annotations

import json
import re
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


BASE_DIR = Path(__file__).resolve().parent
WORKSPACE_DIR = BASE_DIR.parents[2]
NUTRITION_PATH = WORKSPACE_DIR / "data" / "recipe_and_nutrition" / "nutrition_data_categorized.json"
INPUT_PATH = BASE_DIR / "corrected_issue_recipes_from_professional_report.json"
OUTPUT_PATH = BASE_DIR / "corrected_issue_recipes_match_reviewed.json"

BAD_MATCH_NAME_KEYWORDS = (
    "麵包",
    "口糧",
    "麥片",
    "餛飩",
    "炒飯",
    "肉圓",
    "豆腐",
    "酥",
    "脯",
    "鬆餅",
)

EXACT_OVERRIDES = {
    "蘑菇": "洋菇",
    "洋菇": "洋菇",
    "吉利丁片": "吉利丁片",
    "吉利丁": "吉利丁片",
    "明膠": "吉利丁片",
    "肉鬆": "豬肉鬆",
    "紅糟燒肉片": "叉燒肉",
    "雞蛋": "雞蛋平均值",
    "全蛋": "雞蛋平均值",
    "蛋": "雞蛋平均值",
    "土雞蛋": "土雞蛋",
    "水煮蛋": "雞水煮蛋",
    "雞胸肉": "里肌肉(肉雞)",
    "雞腿肉": "去皮去骨雞腿(肉雞)",
    "雞肉": "去皮去骨雞腿(肉雞)",
    "帶骨雞肉": "骨腿平均值",
    "雞里肌": "里肌肉(肉雞)",
    "煎蛋捲": "雞蛋平均值",
    "常溫生雞蛋": "雞蛋平均值",
    "豬肉片": "豬後腿肉",
    "干貝": "干貝(冷凍)",
    "日本生干貝": "干貝(冷凍)",
    "小熱狗": "熱狗",
    "熱狗": "熱狗",
    "小黃瓜": "花胡瓜(有機)",
    "小黃瓜絲": "花胡瓜(有機)",
    "白菜": "結球白菜平均值",
    "大白菜": "結球白菜平均值",
    "地瓜": "紅肉甘藷",
    "甘藷": "紅肉甘藷",
    "大片海苔": "壽司海苔片",
    "海苔": "壽司海苔片",
    "壽司竹簾": None,
    "生粉": "太白粉",
    "鮮奶油": "奶油(液態)",
    "蝦仁": "草蝦仁",
}


def main() -> None:
    foods = FoodCatalog(json.loads(NUTRITION_PATH.read_text(encoding="utf-8")))
    recipes = json.loads(INPUT_PATH.read_text(encoding="utf-8"))
    changed = []

    for recipe in recipes:
        ingredients = []
        for ingredient in recipe.get("resolved_ingredients", []):
            original = str(ingredient.get("original") or "").strip()
            matched = str(ingredient.get("matched") or "").strip()

            if normalize(original) in {normalize("壽司竹簾")}:
                changed.append([recipe["recipe_id"], original, matched, "<removed non-food>"])
                continue

            replacement = choose_replacement(foods, original, matched)
            if replacement:
                new_name = replacement["樣品名稱"]
                new_id = replacement["整合編號"]
                if matched != new_name or ingredient.get("整合編號") != new_id:
                    changed.append([recipe["recipe_id"], original, matched, new_name])
                ingredient["matched"] = new_name
                ingredient["整合編號"] = new_id
                ingredient["method"] = "Professional match review"
            ingredients.append(ingredient)
        recipe["resolved_ingredients"] = ingredients

    OUTPUT_PATH.write_text(json.dumps(recipes, ensure_ascii=False, indent=2), encoding="utf-8")
    invalid = validate_ids(recipes, foods)
    print(f"輸出食譜數: {len(recipes)}")
    print(f"修正/移除 mapping 數: {len(changed)}")
    print(f"無效整合編號: {len(invalid)}")
    print(f"輸出位置: {OUTPUT_PATH}")
    print(json.dumps(changed[:80], ensure_ascii=False, indent=2))
    if invalid:
        print(json.dumps(invalid[:20], ensure_ascii=False, indent=2))


class FoodCatalog:
    def __init__(self, nutrition_data: Dict[str, List[Dict[str, Any]]]) -> None:
        self.rows = [row for rows in nutrition_data.values() for row in rows if isinstance(row, dict)]
        self.valid_ids = {str(row.get("整合編號")) for row in self.rows}
        self.by_name: Dict[str, Dict[str, Any]] = {}
        for row in self.rows:
            for name in names_for_row(row):
                self.by_name.setdefault(normalize(name), row)

    def exact(self, name: str) -> Optional[Dict[str, Any]]:
        return self.by_name.get(normalize(name))

    def best(self, original: str) -> Optional[Dict[str, Any]]:
        original_n = normalize(original)
        if not original_n:
            return None

        candidates = []
        for row in self.rows:
            for name in names_for_row(row):
                name_n = normalize(name)
                score = similarity(original_n, name_n)
                if original_n == name_n:
                    score += 1.0
                elif original_n in name_n or name_n in original_n:
                    score += 0.15
                if is_processed_bad_for_original(original_n, name_n):
                    score -= 0.45
                if same_food_family(original_n, name_n):
                    score += 0.2
                candidates.append((score, len(name_n), row))
        candidates.sort(key=lambda item: (item[0], -item[1]), reverse=True)
        return candidates[0][2] if candidates and candidates[0][0] >= 0.55 else None


def choose_replacement(foods: FoodCatalog, original: str, matched: str) -> Optional[Dict[str, Any]]:
    original_n = normalize(original)
    override = lookup_override(original)
    if override is None and original_n in {normalize("壽司竹簾")}:
        return None
    if override:
        food = foods.exact(override)
        if food:
            return food

    if match_is_suspicious(original, matched):
        exact_original = foods.exact(original)
        if exact_original:
            return exact_original
    return foods.exact(matched)


def lookup_override(original: str) -> Optional[str]:
    original_n = normalize(original)
    for key, value in EXACT_OVERRIDES.items():
        if normalize(key) == original_n:
            return value
    return None


def match_is_suspicious(original: str, matched: str) -> bool:
    original_n = normalize(original)
    matched_n = normalize(matched)
    if not original_n or not matched_n:
        return True
    if original_n == matched_n:
        return False
    if any(keyword in matched and keyword not in original for keyword in BAD_MATCH_NAME_KEYWORDS):
        return True
    if similarity(original_n, matched_n) < 0.45:
        return True
    return False


def is_processed_bad_for_original(original: str, candidate: str) -> bool:
    return any(normalize(keyword) in candidate and normalize(keyword) not in original for keyword in BAD_MATCH_NAME_KEYWORDS)


def same_food_family(original: str, candidate: str) -> bool:
    families = [
        ("菇", "蘑菇", "洋菇", "香菇"),
        ("蛋", "雞蛋", "鴨蛋"),
        ("肉鬆", "豬肉鬆", "肉鬆"),
        ("蝦仁", "草蝦仁", "明蝦仁", "紅蝦仁"),
        ("海苔", "紫菜", "壽司海苔"),
        ("粉", "太白粉", "玉米粉", "馬鈴薯粉"),
    ]
    return any(any(normalize(term) in original for term in family) and any(normalize(term) in candidate for term in family) for family in families)


def names_for_row(row: Dict[str, Any]) -> List[str]:
    names = [str(row.get("樣品名稱") or "")]
    alias = row.get("俗名")
    if alias:
        names.extend(re.split(r"[,、/，；;]", str(alias)))
    return [name.strip() for name in names if name and name.strip()]


def validate_ids(recipes: List[Dict[str, Any]], foods: FoodCatalog) -> List[Tuple[str, str, str]]:
    invalid = []
    for recipe in recipes:
        for ingredient in recipe.get("resolved_ingredients", []):
            food_id = str(ingredient.get("整合編號"))
            if food_id not in foods.valid_ids:
                invalid.append((recipe.get("recipe_id"), ingredient.get("matched"), food_id))
    return invalid


def normalize(value: str) -> str:
    return re.sub(r"\s+", "", str(value or "").strip())


def similarity(left: str, right: str) -> float:
    return SequenceMatcher(None, left, right).ratio()


if __name__ == "__main__":
    main()
