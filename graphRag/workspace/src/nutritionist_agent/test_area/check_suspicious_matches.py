from __future__ import annotations

import json
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
PATH = BASE_DIR / "corrected_issue_recipes_match_reviewed.json"


def main() -> None:
    data = json.loads(PATH.read_text(encoding="utf-8"))
    bad_words = ["麵包", "麥片", "餛飩", "炒飯", "肉圓", "豆腐", "酥", "脯"]
    suspicious = []
    for recipe in data:
        for ingredient in recipe.get("resolved_ingredients", []):
            original = str(ingredient.get("original", ""))
            matched = str(ingredient.get("matched", ""))
            if any(word in matched and word not in original for word in bad_words):
                suspicious.append((recipe["recipe_id"], original, matched, ingredient.get("整合編號")))
    print(len(suspicious))
    print(json.dumps(suspicious[:120], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
