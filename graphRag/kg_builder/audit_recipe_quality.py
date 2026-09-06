from __future__ import annotations

import argparse
import base64
import json
import math
import re
import sys
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from datetime import datetime, timezone
from itertools import combinations
from pathlib import Path
from typing import Any, Dict, Iterable, List, Set


BASE_DIR = Path(__file__).resolve().parents[2]
DATA_DIR = BASE_DIR / "data"
RECIPE_DATA_DIR = DATA_DIR / "recipe_and_nutrition"
NUTRITION_DATA_PATH = RECIPE_DATA_DIR / "nutrition_data_categorized.json"
OUTPUT_DIR = BASE_DIR / "output" / "recipe_quality_audit"

NUTRIENT_KEYS = {
    "energy_kcal": ("熱量", "energy", "calorie", "kcal"),
    "sodium_mg": ("鈉", "sodium"),
    "protein_g": ("粗蛋白", "蛋白質", "protein"),
    "fat_g": ("粗脂肪", "脂肪", "total fat"),
    "saturated_fat_g": ("飽和脂肪", "saturated fat"),
    "carb_g": ("總碳水化合物", "碳水化合物", "醣類", "carbohydrate", "carb"),
    "sugar_g": ("糖質總量", "糖", "sugar"),
    "fiber_g": ("膳食纖維", "dietary fiber", "fiber"),
}

MAIN_INGREDIENT_GROUPS = {
    "米飯/穀物": ("飯", "粥", "丼", "米", "糯米", "燕麥"),
    "麵/粉": ("麵", "麵線", "米粉", "冬粉", "粉條", "河粉", "拉麵", "烏龍", "意麵", "板條"),
    "雞肉": ("雞", "雞腿", "雞胸", "雞排", "雞翅"),
    "豬肉": ("豬", "肉燥", "滷肉", "排骨", "豬腳", "培根", "火腿"),
    "牛肉": ("牛", "牛排", "牛肉"),
    "羊肉": ("羊",),
    "魚/海鮮": ("魚", "蝦", "蟹", "蚵", "蛤", "牡蠣", "魷", "花枝", "透抽", "鮭", "鯖", "鯛", "鱈", "干貝"),
    "蛋": ("蛋", "蛋餅", "蛋塔"),
    "豆製品": ("豆腐", "豆干", "豆皮", "豆漿", "毛豆", "黃豆"),
    "乳品/奶": ("奶", "乳", "起司", "乳酪", "鮮奶油"),
}

NON_SAVORY_MARKERS = (
    "飲", "茶", "咖啡", "果汁", "奶昔", "冰沙", "甜湯", "甜品", "蛋糕", "餅乾", "布丁", "豆花", "冰淇淋", "派", "塔",
)
GENERIC_TITLE_WORDS = (
    "招牌", "特製", "特選", "精選", "經典", "古早味", "人氣", "風味", "家常", "台式", "臺式", "日式", "韓式", "美式", "義式",
    "原味", "香", "酥", "脆", "嫩", "鮮", "濃", "清", "紅燒", "清燉", "麻辣", "酸辣", "蒜香", "椒麻", "照燒", "沙茶",
)
SEASONING_MARKERS = (
    "鹽", "醬油", "醬", "油", "糖", "醋", "胡椒", "辣椒", "香辛", "蒜", "蔥", "薑", "米酒", "酒", "高湯", "湯塊", "味精",
)
BASE_MARKERS = ("水", "高湯", "湯", "茶湯", "牛奶", "鮮乳", "豆漿")
MARKETING_MARKERS = ("招牌", "霸王", "超級", "豪華", "頂級", "必吃", "爆", "夢幻", "神級", "店長", "一號", "1號", "A餐", "B餐", "套餐")

THRESHOLDS = {
    "energy_warning_kcal": 1200,
    "energy_fail_kcal": 1800,
    "sodium_warning_mg": 1200,
    "sodium_fail_mg": 2400,
    "fat_warning_g": 50,
    "fat_fail_g": 80,
    "saturated_fat_warning_g": 15,
    "saturated_fat_fail_g": 25,
    "sugar_warning_g": 35,
    "sugar_fail_g": 60,
    "total_weight_warning_g": 1800,
    "total_weight_fail_g": 2500,
    "nutrition_energy_mismatch_ratio": 0.25,
    "similarity_warning": 0.85,
}


def text(value: Any) -> str:
    return str(value or "").strip()


def number(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (TypeError, ValueError):
        return None


def normalize_text(value: Any) -> str:
    return re.sub(r"\s+", "", text(value)).lower()


def is_gram_unit(value: Any) -> bool:
    return normalize_text(value) in {"g", "克", "公克", "gram", "grams"}


def food_ids_from_source(path: Path) -> Set[str]:
    source = json.loads(path.read_text(encoding="utf-8"))
    ids: Set[str] = set()
    for rows in source.values():
        if not isinstance(rows, list):
            continue
        for row in rows:
            if isinstance(row, dict) and text(row.get("整合編號")):
                ids.add(text(row["整合編號"]).splitlines()[0].strip())
    return ids


def nutrient_key(name: Any) -> str | None:
    value = normalize_text(name)
    for key, aliases in NUTRIENT_KEYS.items():
        if any(value == normalize_text(alias) for alias in aliases):
            return key
    return None


def title_groups(recipe_name: str) -> List[str]:
    return [group for group, tokens in MAIN_INGREDIENT_GROUPS.items() if any(token in recipe_name for token in tokens)]


def is_non_savory(recipe_name: str) -> bool:
    return any(marker in recipe_name for marker in NON_SAVORY_MARKERS)


def ingredient_text(ingredient: Dict[str, Any]) -> str:
    return " ".join(
        text(ingredient.get(key))
        for key in ("original_name", "matched_food_name", "food_name")
    )


def format_food_list(ingredients: List[Dict[str, Any]]) -> str:
    parts = []
    for item in sorted(ingredients, key=lambda row: (row.get("order") or 9999, row.get("original_name") or "")):
        amount = item.get("amount_per_serving")
        if amount is None:
            amount = item.get("amount")
        parts.append(f"{text(item.get('original_name')) or text(item.get('matched_food_name'))} {amount:g}g" if amount is not None else f"{text(item.get('original_name'))} [缺份量]")
    return "; ".join(parts)


def build_similarity_map(recipes: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    inverted: Dict[str, Set[str]] = defaultdict(set)
    recipe_sets: Dict[str, Set[str]] = {}
    recipe_names: Dict[str, str] = {}
    for recipe in recipes:
        rid = recipe["recipe_id"]
        ids = {text(item.get("matched_food_id")) for item in recipe["ingredients"] if text(item.get("matched_food_id"))}
        recipe_sets[rid] = ids
        recipe_names[rid] = recipe["recipe_name"]
        for food_id in ids:
            inverted[food_id].add(rid)

    common_counts: Counter[tuple[str, str]] = Counter()
    for ids in inverted.values():
        members = sorted(ids)
        if len(members) > 1:
            for left, right in combinations(members, 2):
                common_counts[(left, right)] += 1

    result: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for (left, right), common in common_counts.items():
        union = len(recipe_sets[left] | recipe_sets[right])
        similarity = common / union if union else 0.0
        if similarity >= THRESHOLDS["similarity_warning"] and recipe_names[left] != recipe_names[right]:
            result[left].append({"recipe_id": right, "recipe_name": recipe_names[right], "similarity": round(similarity, 3)})
            result[right].append({"recipe_id": left, "recipe_name": recipe_names[left], "similarity": round(similarity, 3)})
    for rid in result:
        result[rid].sort(key=lambda row: (-row["similarity"], row["recipe_id"]))
        result[rid] = result[rid][:5]
    return result


def load_env() -> Dict[str, str]:
    values: Dict[str, str] = {}
    candidates = [BASE_DIR.parent / ".env", BASE_DIR.parents[1] / ".env", BASE_DIR / ".env"]
    for path in candidates:
        if not path.exists():
            continue
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def run_cypher(query: str) -> List[Dict[str, Any]]:
    env = load_env()
    uri = env.get("NEO4J_URI", "neo4j://127.0.0.1:7687")
    host = uri.split("://", 1)[-1].split(":", 1)[0].split("/", 1)[0]
    http_url = f"http://{host}:7474/db/{env.get('NEO4J_DATABASE', 'neo4j')}/tx/commit"
    user = env.get("NEO4J_USER", "neo4j")
    password = env.get("NEO4J_PASSWORD", "")
    auth = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
    payload = json.dumps({"statements": [{"statement": query, "parameters": {}}]}).encode("utf-8")
    request = urllib.request.Request(
        http_url,
        data=payload,
        headers={"Content-Type": "application/json", "Authorization": f"Basic {auth}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Neo4j HTTP API unavailable at {http_url}: {exc}") from exc
    if body.get("errors"):
        raise RuntimeError(json.dumps(body["errors"], ensure_ascii=False))
    result = body.get("results", [{}])[0]
    columns = result.get("columns", [])
    rows = []
    for entry in result.get("data", []):
        row = entry.get("row", entry) if isinstance(entry, dict) else entry
        rows.append(dict(zip(columns, row)))
    return rows


def query_graph() -> tuple[List[Dict[str, Any]], Dict[str, List[Dict[str, Any]]]]:
    recipe_query = """
    MATCH (d:Dish)-[c:CONTAINS]->(i:Ingredient)
    OPTIONAL MATCH (i)-[:MAPS_TO]->(f:FoodItem)
    RETURN d.recipe_id AS recipe_id, d.name AS recipe_name, d.servings AS servings,
           collect({
             ingredient_key: i.name,
             original_name: i.original_name,
             matched_food_id: i.matched_food_id,
             matched_food_name: i.matched_food_name,
             amount: c.amount,
             amount_value: c.amount_value,
             amount_unit: c.amount_unit,
             unit: c.unit,
             amount_per_serving: c.amount_per_serving,
             amount_note: c.amount_note,
             order: c.order,
             food_id: f.food_id,
             food_name: f.name,
             food_category: f.category
           }) AS ingredients
    ORDER BY d.recipe_id
    """
    nutrient_query = """
    MATCH (f:FoodItem)-[r:HAS_NUTRITION]->(n:Nutrition)
    RETURN f.food_id AS food_id,
           collect({nutrition_id: n.nutrition_id, name: n.name, name_zh: n.name_zh,
                    unit: n.unit, amount_per_100g: r.amount_per_100g}) AS nutrients
    """
    recipe_rows = run_cypher(recipe_query)
    nutrient_rows = run_cypher(nutrient_query)
    food_nutrients = {text(row["food_id"]): row.get("nutrients", []) for row in nutrient_rows if text(row.get("food_id"))}
    recipes = []
    for row in recipe_rows:
        ingredients = [dict(item) for item in row.get("ingredients", []) if item.get("ingredient_key")]
        recipes.append(
            {
                "recipe_id": text(row.get("recipe_id")),
                "recipe_name": text(row.get("recipe_name")),
                "servings": row.get("servings"),
                "ingredients": ingredients,
                "food_nutrients": food_nutrients,
            }
        )
    return recipes, food_nutrients


def calculate_nutrition(recipe: Dict[str, Any]) -> Dict[str, float | None]:
    totals: Dict[str, float] = defaultdict(float)
    for ingredient in recipe["ingredients"]:
        food_id = text(ingredient.get("food_id")) or text(ingredient.get("matched_food_id"))
        amount = number(ingredient.get("amount_per_serving"))
        if amount is None:
            amount = number(ingredient.get("amount"))
        if not food_id or amount is None:
            continue
        for nutrient in recipe["food_nutrients"].get(food_id, []):
            key = nutrient_key(nutrient.get("name_zh") or nutrient.get("name"))
            value = number(nutrient.get("amount_per_100g"))
            if key and value is not None:
                unit = normalize_text(nutrient.get("unit"))
                if key.endswith("_g") and unit == "mg":
                    value /= 1000.0
                elif key == "sodium_mg" and unit == "g":
                    value *= 1000.0
                totals[key] += amount * value / 100.0
    return {key: round(totals.get(key, 0.0), 2) for key in NUTRIENT_KEYS}


def audit_recipe(recipe: Dict[str, Any], source_food_ids: Set[str], similar: Dict[str, List[Dict[str, Any]]]) -> Dict[str, Any]:
    fails: List[str] = []
    warnings: List[str] = []
    recommendations: List[str] = []
    rules: Set[str] = set()
    ingredients = recipe["ingredients"]
    name = recipe["recipe_name"]
    texts = [ingredient_text(item) for item in ingredients]
    combined = " ".join(texts)
    servings = number(recipe.get("servings"))

    # 7. Every quantity must be explicit grams.
    bad_amounts = []
    for item in ingredients:
        amount = number(item.get("amount_per_serving"))
        if amount is None:
            amount = number(item.get("amount"))
        unit = text(item.get("amount_unit") or item.get("unit"))
        if amount is None or amount <= 0 or not is_gram_unit(unit):
            bad_amounts.append(f"{text(item.get('original_name')) or text(item.get('matched_food_name'))} ({amount if amount is not None else '缺少'} {unit or '缺少單位'})")
    if bad_amounts:
        rules.add("7")
        fails.append("食材份量不完整或不是克數(g)：" + ", ".join(bad_amounts))
        recommendations.append("補上每項食材的一人份克數，並統一使用 g 作為單位。")

    # 8. A non-one-serving source is acceptable when every relationship stores a
    # valid per-serving quantity. This is the value used by the calculator.
    per_serving_missing = [
        text(item.get("original_name")) or text(item.get("matched_food_name"))
        for item in ingredients
        if number(item.get("amount_per_serving")) is None or number(item.get("amount_per_serving")) <= 0
    ]
    if servings != 1 and per_serving_missing:
        rules.add("8")
        if servings is None:
            fails.append("servings 缺失，且部分食材沒有有效的 amount_per_serving，無法確認每份份量。")
        else:
            fails.append(f"servings={servings:g}，且部分食材沒有有效的 amount_per_serving：" + ", ".join(per_serving_missing))
        recommendations.append("保留原始 servings 也可以，但必須為每個 CONTAINS relationship 補上有效的 amount_per_serving。")

    # 9. Food IDs must exist in the source nutrition data.
    invalid_ids = []
    unmapped = []
    no_nutrition = []
    for item in ingredients:
        item_name = text(item.get("original_name")) or text(item.get("matched_food_name"))
        food_id = text(item.get("food_id")) or text(item.get("matched_food_id"))
        if not food_id:
            unmapped.append(item_name)
        elif food_id not in source_food_ids:
            invalid_ids.append(f"{item_name} -> {food_id}")
        elif not recipe["food_nutrients"].get(food_id):
            no_nutrition.append(f"{item_name} -> {food_id}")
    if unmapped or invalid_ids:
        rules.add("9")
        details = []
        if unmapped:
            details.append("未建立 MAPS_TO：" + ", ".join(unmapped))
        if invalid_ids:
            details.append("nutrition_data_categorized.json 不存在的編號：" + ", ".join(invalid_ids))
        fails.append("食材編號對應錯誤；" + "；".join(details))
        recommendations.append("只保留 nutrition_data_categorized.json 中存在的整合編號，重新建立 Ingredient -> FoodItem 對應。")
    if no_nutrition:
        rules.add("2")
        fails.append("FoodItem 沒有可用營養成分，無法完成料理營養計算：" + ", ".join(no_nutrition))
        recommendations.append("補齊該 FoodItem 的 HAS_NUTRITION 資料後再評估營養比例。")

    # 1. Main title signals should appear in at least one ingredient.
    missing_groups = []
    for group in title_groups(name):
        tokens = MAIN_INGREDIENT_GROUPS[group]
        if not any(token in combined for token in tokens):
            missing_groups.append(group)
    if missing_groups:
        rules.add("1")
        fails.append(f"料理名稱暗示的主食材類別未出現在食譜：{', '.join(missing_groups)}。")
        recommendations.append("補入名稱所指的主食材，或修改料理名稱使其與實際食材一致。")

    # 5. Basic completeness check for restaurant-style savory dishes.
    if not is_non_savory(name) and len(ingredients) >= 3:
        has_seasoning = any(any(marker in value for marker in SEASONING_MARKERS) for value in texts)
        if not has_seasoning:
            rules.add("5")
            warnings.append("食材清單看不到明確的調味料、油脂或湯底，可能未完整列出外食料理常用調味。")
            recommendations.append("確認並補列鹽、醬油、油、醋、糖、香辛料或湯底等實際使用項目與克數。")

    # 3. Basic restaurant preparation plausibility.
    fried_markers = ("炸", "酥", "鹽酥", "天婦羅")
    if any(marker in name for marker in fried_markers) and not any("油" in value for value in texts):
        rules.add("3")
        warnings.append("名稱包含炸/酥等製作方式，但食材清單未列出油脂，可能低估外食熱量與脂肪。")
        recommendations.append("若為油炸或大量煎炸，補列實際使用油脂；若已瀝油，仍應以合理吸油量估算。")
    if "湯" in name and not any(any(marker in value for marker in BASE_MARKERS) for value in texts):
        rules.add("3")
        warnings.append("名稱為湯品，但清單未看到水、高湯或湯底，製作內容可能不完整。")
        recommendations.append("補列水、高湯或湯底的克數，並確認湯汁是否計入一人份。")

    # 6. Store-specific marketing names are review items, not automatically invalid.
    marketing = [marker for marker in MARKETING_MARKERS if marker in name]
    if marketing:
        rules.add("6")
        warnings.append("料理名稱含有較強的店家/行銷命名訊號（" + ", ".join(marketing) + "），不一定是標準通用菜名。")
        recommendations.append("若要作為通用食譜資料，改用可由一般使用者理解的標準菜名，將店家特色放到備註欄。")

    # 4. Very similar ingredient sets across different recipes.
    similar_rows = similar.get(recipe["recipe_id"], [])
    if similar_rows:
        rules.add("4")
        peers = "、".join(f"{row['recipe_name']} ({row['similarity']:.0%})" for row in similar_rows[:3])
        warnings.append(f"食材組合與其他料理高度相似，可能是模板化或重複資料：{peers}。")
        recommendations.append("人工確認料理名稱、份量或醬料是否真的不同；若只是同一底料，應避免建立重複食譜。")

    nutrition = calculate_nutrition(recipe)
    total_weight = sum(number(item.get("amount_per_serving")) or number(item.get("amount")) or 0 for item in ingredients)

    # 2. Nutrition health-risk checks. High nutrients can be normal for restaurant food,
    # so they remain review warnings; they do not become hard data failures by themselves.
    energy = nutrition["energy_kcal"]
    sodium = nutrition["sodium_mg"]
    fat = nutrition["fat_g"]
    saturated = nutrition["saturated_fat_g"]
    sugar = nutrition["sugar_g"]
    if energy > THRESHOLDS["energy_fail_kcal"]:
        rules.add("2")
        warnings.append(f"估算每份熱量約 {energy:.0f} kcal，明顯偏高；但若料理屬正常外食大份量，食譜仍可能成立，需人工確認份量。")
        recommendations.append("優先核對油脂、炸物、加工肉、濃醬與主食份量；若資料無誤，可保留並標註高熱量風險。")
    elif energy > THRESHOLDS["energy_warning_kcal"]:
        rules.add("2")
        warnings.append(f"估算每份熱量約 {energy:.0f} kcal，偏高，可能來自外食常見的油脂、濃醬或大份主食。")
        recommendations.append("確認油、醬料與主食克數；必要時減少油脂或將主食份量調整到一般單餐範圍。")
    if sodium > THRESHOLDS["sodium_fail_mg"]:
        rules.add("2")
        warnings.append(f"估算每份鈉約 {sodium:.0f} mg，已超過每日 2,400 mg 上限；屬高鈉健康風險，但正常外食料理仍可能出現，不單獨判為 FAIL。")
        recommendations.append("核對醬油、鹽、湯塊、加工肉與濃湯用量；資料無誤時可保留食譜並標註高鈉或提供少鹽版本。")
    elif sodium > THRESHOLDS["sodium_warning_mg"]:
        rules.add("2")
        warnings.append(f"估算每份鈉約 {sodium:.0f} mg，已達每日 2,400 mg 上限的一半，外食食譜需人工確認。")
        recommendations.append("檢查鹽、醬油、湯塊、加工食品與湯汁份量，並考慮減少調味或提供少鹽版本。")
    if fat > THRESHOLDS["fat_fail_g"]:
        rules.add("2")
        warnings.append(f"估算每份脂肪約 {fat:.1f} g，顯著偏高；若符合炸物、肥肉或濃醬外食型態，食譜仍可能成立，不單獨判為 FAIL。")
        recommendations.append("核對炸油、奶油、肥肉、起司與高脂醬料的克數；資料無誤時可保留並標註高油脂風險。")
    elif fat > THRESHOLDS["fat_warning_g"]:
        rules.add("2")
        warnings.append(f"估算每份脂肪約 {fat:.1f} g，偏高，可能是外食高油料理但需確認份量。")
        recommendations.append("人工核對油脂與肥肉份量，必要時降低油量或改用較瘦蛋白質。")
    if saturated > THRESHOLDS["saturated_fat_fail_g"]:
        rules.add("2")
        warnings.append(f"估算每份飽和脂肪約 {saturated:.1f} g，顯著偏高；若符合起司、肥肉或油炸外食型態，食譜仍可能成立，不單獨判為 FAIL。")
        recommendations.append("核對奶油、鮮奶油、起司、肥肉與油炸配料的克數；資料無誤時可保留並標註高飽和脂肪風險。")
    elif saturated > THRESHOLDS["saturated_fat_warning_g"]:
        rules.add("2")
        warnings.append(f"估算每份飽和脂肪約 {saturated:.1f} g，偏高。")
        recommendations.append("確認高脂乳品與肥肉份量，並考慮減量。")
    if sugar > THRESHOLDS["sugar_fail_g"]:
        rules.add("2")
        warnings.append(f"估算每份糖約 {sugar:.1f} g，顯著偏高；若為甜飲或甜點，食譜仍可能成立，但有高糖健康風險。")
        recommendations.append("核對砂糖、糖漿、果醬、含糖飲料基底與甜味配料；資料無誤時可保留並標註高糖風險。")
    elif sugar > THRESHOLDS["sugar_warning_g"]:
        rules.add("2")
        warnings.append(f"估算每份糖約 {sugar:.1f} g，偏高，尤其需注意飲料與甜點。")
        recommendations.append("減少砂糖、糖漿或果醬，並確認飲料是否使用含糖奶精或甜味基底。")
    if total_weight > THRESHOLDS["total_weight_fail_g"]:
        rules.add("2")
        fails.append(f"每份食材總重約 {total_weight:.0f} g，遠高於一般單份料理篩檢範圍，可能重複計入湯水或份量。")
        recommendations.append("核對是否把整鍋湯底、煮食損耗前重量或多份食材誤寫成一人份。")
    elif total_weight > THRESHOLDS["total_weight_warning_g"]:
        rules.add("2")
        warnings.append(f"每份食材總重約 {total_weight:.0f} g，偏高，需確認是否真的為一人份。")
        recommendations.append("確認湯水、飲料體積與主食克數是否為一人份可食重量。")

    # Check energy against macronutrient-derived energy when enough data exists.
    macro_energy = nutrition["protein_g"] * 4 + nutrition["carb_g"] * 4 + nutrition["fat_g"] * 9
    if energy > 50 and macro_energy > 50:
        mismatch = abs(energy - macro_energy) / energy
        if mismatch > THRESHOLDS["nutrition_energy_mismatch_ratio"]:
            rules.add("2")
            warnings.append(f"熱量與三大營養素反推值差異約 {mismatch:.0%}，可能有營養欄位缺漏、單位或食材份量問題。")
            recommendations.append("核對 FoodItem 營養單位、食材克數與熱量/三大營養素來源欄位。")

    status = "FAIL" if fails else "WARNING" if warnings else "PASS"
    confidence = 0.98 if status == "FAIL" else 0.78 if status == "WARNING" else 0.95
    return {
        "recipe_id": recipe["recipe_id"],
        "recipe_name": name,
        "status": status,
        "confidence": confidence,
        "servings": servings,
        "ingredient_count": len(ingredients),
        "total_ingredient_g": round(total_weight, 1),
        "energy_kcal": nutrition["energy_kcal"],
        "sodium_mg": nutrition["sodium_mg"],
        "protein_g": nutrition["protein_g"],
        "fat_g": nutrition["fat_g"],
        "saturated_fat_g": nutrition["saturated_fat_g"],
        "carb_g": nutrition["carb_g"],
        "sugar_g": nutrition["sugar_g"],
        "fiber_g": nutrition["fiber_g"],
        "title_groups": ", ".join(title_groups(name)),
        "ingredients": format_food_list(ingredients),
        "fail_reasons": "\n".join(dict.fromkeys(fails)),
        "warning_reasons": "\n".join(dict.fromkeys(warnings)),
        "recommendations": "\n".join(dict.fromkeys(recommendations)),
        "rules": ", ".join(sorted(rules, key=int)),
        "similar_recipes": "; ".join(f"{row['recipe_name']} ({row['similarity']:.0%})" for row in similar_rows),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit every Neo4j recipe before production use.")
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR)
    args = parser.parse_args()

    source_food_ids = food_ids_from_source(NUTRITION_DATA_PATH)
    recipes, food_nutrients = query_graph()

    similar = build_similarity_map(recipes)
    audit_rows = [audit_recipe(recipe, source_food_ids, similar) for recipe in recipes]
    ingredients = []
    nutrition_rows = []
    for recipe, audit in zip(recipes, audit_rows):
        for item in recipe["ingredients"]:
            ingredients.append(
                {
                    "recipe_id": recipe["recipe_id"],
                    "recipe_name": recipe["recipe_name"],
                    "ingredient_name": text(item.get("original_name")) or text(item.get("matched_food_name")),
                    "matched_food_name": text(item.get("matched_food_name")),
                    "food_id": text(item.get("food_id")) or text(item.get("matched_food_id")),
                    "amount_g": number(item.get("amount_per_serving")) or number(item.get("amount")),
                    "amount_unit": text(item.get("amount_unit") or item.get("unit")),
                    "source_id_exists": (text(item.get("food_id")) or text(item.get("matched_food_id"))) in source_food_ids,
                }
            )
        nutrition_rows.append({"recipe_id": recipe["recipe_id"], "recipe_name": recipe["recipe_name"], **{key: audit[key] for key in NUTRIENT_KEYS}, "total_ingredient_g": audit["total_ingredient_g"]})

    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "recipe_count": len(audit_rows),
        "ingredient_relation_count": len(ingredients),
        "source_food_id_count": len(source_food_ids),
        "fooditem_count_in_graph": len(food_nutrients),
        "status_counts": dict(Counter(row["status"] for row in audit_rows)),
        "source_food_ids_missing_in_graph": sorted(source_food_ids - set(food_nutrients)),
        "graph_food_ids_not_in_source": sorted(set(food_nutrients) - source_food_ids),
        "thresholds": THRESHOLDS,
        "sources": [
            {"name": "nutrition_data_categorized.json", "path": str(NUTRITION_DATA_PATH)},
            {"name": "衛生福利部國民健康署：正確飲食習慣", "url": "https://www.hpa.gov.tw/Pages/Detail.aspx?nodeid=543&pid=8365&sid=718"},
            {"name": "衛生福利部國民健康署：外食中主食如何吃得更健康", "url": "https://www.hpa.gov.tw/Pages/Detail.aspx?nodeid=4560&pid=16720&sid=16717"},
        ],
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "recipe_quality_audit.json").write_text(json.dumps({"summary": summary, "recipes": audit_rows, "ingredients": ingredients, "nutrition": nutrition_rows}, ensure_ascii=False, indent=2), encoding="utf-8")
    (args.output_dir / "recipe_quality_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
