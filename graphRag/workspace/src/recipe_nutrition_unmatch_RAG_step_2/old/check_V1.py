import json

# 讀取原始的 JSON 檔案
file_path = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG_step_2\data\input\20260424_124834\resolved_recipes_output.json"
with open(file_path, "r", encoding="utf-8") as f:
    data = json.load(f)

results = []
total_none_ingredients = 0  # 新增一個變數來計算總食材數

# 遍歷所有食譜
for recipe in data:
    missing_ingredients = []

    # 檢查每個食材的整合編號
    for ing in recipe.get("resolved_ingredients", []):
        if ing.get("整合編號") == "None" or ing.get("整合編號") is None:
            missing_ingredients.append(ing)
            total_none_ingredients += 1  # 只要找到一個 None，總食材數就 +1

    # 如果有找到整合編號為 None 的食材，則將所需資料抓出來
    if missing_ingredients:
        results.append({
            "recipe_id": recipe.get("recipe_id"),
            "recipe_name": recipe.get("recipe_name"),
            "resolved_ingredients": missing_ingredients
        })

# 將結果儲存成新的 JSON 檔案
file_output_path = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG_step_2\data\output\missing_integration_id.json"
with open(file_output_path, "w", encoding="utf-8") as f:
    json.dump(results, f, ensure_ascii=False, indent=2)

print(f"總共找到 {len(results)} 筆含有整合編號為 None 的食譜資料。")
print(f"其中，整合編號為 None 的食材總共有 {total_none_ingredients} 個。")
