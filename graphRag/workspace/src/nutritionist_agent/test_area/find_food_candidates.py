from __future__ import annotations

import json
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
WORKSPACE_DIR = BASE_DIR.parents[2]
NUTRITION_PATH = WORKSPACE_DIR / "data" / "recipe_and_nutrition" / "nutrition_data_categorized.json"


def main() -> None:
    rows = [row for values in json.loads(NUTRITION_PATH.read_text(encoding="utf-8")).values() for row in values]
    terms = [
        "蘑",
        "洋菇",
        "吉利丁",
        "洋菜",
        "豬肉鬆",
        "豬肉酥",
        "雞蛋平均值",
        "雞蛋豆腐",
        "白米",
        "白飯",
        "義大利麵",
        "通心麵",
        "意麵",
        "太白粉",
        "奶油(液態)",
        "草蝦仁",
        "雞胸",
        "雞腿",
        "雞肉",
        "白菜",
        "甘藍",
        "地瓜",
        "甘藷",
        "叉燒",
        "豬後腿",
        "豬肉",
        "梅花肉",
        "里肌肉",
        "小黃瓜",
        "胡瓜",
        "干貝",
        "雞里肌",
    ]
    for term in terms:
        print("---", term)
        for row in rows:
            name = str(row.get("樣品名稱", ""))
            alias = str(row.get("俗名", ""))
            if term in name or term in alias:
                print(row.get("整合編號"), name, row.get("食品分類"), "alias=" + alias)


if __name__ == "__main__":
    main()
