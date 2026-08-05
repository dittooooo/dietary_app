# -*- coding: utf-8 -*-

"""
nutrition_item_classifier.py - V2（修正版）

修正：
1. fallback 不再強制 subtype
2. base food 自動升級 exact_base_food
3. 調味料永遠可查詢
4. 減少 fallback_inferred
5. 修正 processing 誤判
6. canonical_name 更嚴謹
"""

import json
from pathlib import Path


# =============================
# 固定路徑（你可以改這裡）
# =============================

NUTRITION_DATA_PATH = Path(r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_V2\data\input\1_nutrition_data_categorized.json")
OUTPUT_PATH = Path(r"C:\Users\PARALELL\Desktop\code4\workspace\src\nutrition_canonical\output\classified_v2.json")


# =============================
# 規則（精簡但有效）
# =============================

CANONICAL_MAP = {
    "牛奶": ["牛奶", "牛乳", "鮮乳", "鮮奶"],
    "鹽": ["鹽", "食鹽", "鹽巴", "氯化鈉"],
    "糖": ["糖", "砂糖", "蔗糖", "白砂糖"],
    "油": ["油", "植物油", "沙拉油", "食用油"],
    "醬油": ["醬油"],
    "豆腐": ["豆腐"],
    "麵粉": ["麵粉"],
    "番茄": ["番茄", "蕃茄"],
}

FLAVOR_KEYWORDS = ["巧克力", "草莓", "布丁", "香草"]
DERIVED_KEYWORDS = ["醬", "汁", "湯", "粉", "膏"]
SEASONING = ["鹽", "糖", "醬油", "油"]


# =============================
# 工具
# =============================

def normalize(text):
    if not text:
        return ""
    return str(text).strip()


def find_canonical(name):
    for canon, aliases in CANONICAL_MAP.items():
        for a in aliases:
            if a in name:
                return canon
    return None


def contains_any(text, keywords):
    return any(k in text for k in keywords)


# =============================
# 主分類
# =============================

def classify(item):
    name = normalize(item.get("樣品名稱"))
    desc = normalize(item.get("內容物描述"))

    text = name + desc

    canonical = find_canonical(text)

    # === 預設值 ===
    match_type = "unknown"
    is_base = False
    is_default = False
    hidden = True

    # =========================
    # 1️⃣ 有 canonical
    # =========================
    if canonical:

        is_base = True

        # 完全等於
        if name == canonical:
            match_type = "exact_base_food"
            is_default = True
            hidden = False

        # 調味
        elif contains_any(text, FLAVOR_KEYWORDS):
            match_type = "flavored_variant"
            is_default = False
            hidden = True

        # 加工品
        elif contains_any(text, DERIVED_KEYWORDS):
            match_type = "derived_product"
            is_base = False
            is_default = False
            hidden = True

        else:
            match_type = "subtype"
            is_default = True
            hidden = False

    # =========================
    # 2️⃣ 沒 canonical
    # =========================
    else:

        # 嘗試 fallback（但不亂判 subtype）
        match_type = "unknown"
        is_base = False
        is_default = False
        hidden = True

    # =========================
    # 3️⃣ 調味料強制修正
    # =========================
    if canonical in SEASONING:
        is_default = True
        hidden = False

    return {
        "raw_name": name,
        "canonical_name": canonical,
        "match_type": match_type,
        "is_base_food": is_base,
        "is_query_default": is_default,
        "is_hidden": hidden,
    }


# =============================
# 主流程
# =============================

def main():

    data = json.load(open(NUTRITION_DATA_PATH, "r", encoding="utf-8"))

    results = []

    for row in data:
        classified = classify(row)
        results.append(classified)

    json.dump(results, open(OUTPUT_PATH, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

    print(f"done: {len(results)} items")


if __name__ == "__main__":
    main()