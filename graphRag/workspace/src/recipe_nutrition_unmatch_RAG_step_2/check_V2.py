# ==========================================
# V2 版本修改紀錄：
# 1. 擴增篩選條件：除了原有的「整合編號」為 "None" 或空值外，新增了「matched」為 "無對應" 的條件。
# 2. 提取並統計：改為抓出符合條件的 "original" (原始名稱)，並統計這些原始名稱出現的次數。
# 3. 排序與輸出：將各個原始名稱依照出現次數由高至低排序，並儲存為新的 JSON 檔案。
# 用來產生workspace\src\recipe_nutrition_unmatch_RAG_step_2\data\output\missing_integration.json
# ==========================================

import datetime
import json
from collections import Counter

# 讀取原始的 JSON 檔案
file_path = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG_step_2\data\input\20260424_124834\resolved_recipes_output.json"
with open(file_path, "r", encoding="utf-8") as f:
    data = json.load(f)

# 用來收集所有符合條件的 original 名稱
unmatched_originals = []

# 遍歷所有食譜
for recipe in data:
    for ing in recipe.get("resolved_ingredients", []):
        # 條件 1："整合編號"是"None"
        is_none_id = (ing.get("整合編號") == "None" or ing.get("整合編號") is None)
        # 條件 2："matched"是"無對應"
        is_unmatched = (ing.get("matched") == "無對應")

        # 只要符合其中一個條件，就將 original 抓出來
        if is_none_id or is_unmatched:
            original_name = ing.get("original")
            if original_name:
                unmatched_originals.append(original_name)

# 統計各個 original 名稱出現的次數
original_counts = Counter(unmatched_originals)

# 將結果依出現次數由高到低排序轉為字典
sorted_counts = dict(sorted(original_counts.items(),
                     key=lambda item: item[1], reverse=True))

# 儲存統計結果為 JSON (包含原始名稱與對應次數)
timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
file_output_path = f"C:/Users/PARALELL/Desktop/code4/workspace/src/recipe_nutrition_unmatch_RAG_step_2/data/output/missing_integration_{timestamp}.json"
with open(file_output_path, "w", encoding="utf-8") as f:
    json.dump(sorted_counts, f, ensure_ascii=False, indent=2)

print(f"總計符合條件的食材項目有: {len(unmatched_originals)} 項")
print(f"其中不重複的 original 名稱有: {len(sorted_counts)} 種")
for i, (recipe, times) in enumerate(sorted_counts.items()):
    if i < 11:
        print(f"{recipe}:出現{times}次")
