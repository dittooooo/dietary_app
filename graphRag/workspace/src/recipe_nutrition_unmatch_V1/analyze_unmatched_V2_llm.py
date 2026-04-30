
import json
import os
from datetime import datetime
from openai import OpenAI
from tqdm import tqdm  # 引入 tqdm 進度條套件

# ==========================================
# 1. 初始化設定
# ==========================================
# 請替換成您實際的 API Key
client = OpenAI(api_key="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") 
RECIPES_FILE = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch\data\input\recipes.json"

# ==========================================
# 2. 輔助函式：呼叫 LLM 進行正規化
# ==========================================
def normalize_ingredients_with_llm(ingredient_list):
    if not ingredient_list:
        return []
        
    prompt = f"""
    你是一位專業的食品營養學家與資料清理專家。
    請將以下來自食譜的「口語化食材名稱」，轉換為適合用來對應台灣 FDA 食品營養成分資料庫的「核心標準名稱」。

    【處理規則】：
    1. 去除品牌或通路名稱（如：全聯、三元、義美）。
    2. 去除物理切法與狀態（如：丁、片、末、蓉、絲、段、塊）。
    3. 去除包裝與容器型態（如：罐頭、盒裝、真空包、冷凍）。
    4. 若為常見俗名，盡量還原為標準名稱（如：土豆 -> 馬鈴薯、蕃茄 -> 番茄）。
    5. 保留食材的核心屬性（例如：豬絞肉、豬小腸、低筋麵粉）。

    【請務必以 JSON Array 格式回傳】，格式如下：
    [
      {{"raw": "全聯瘦豬絞肉", "normalized": "豬絞肉"}},
      {{"raw": "洋蔥丁", "normalized": "洋蔥"}}
    ]

    【實際輸入】：
    {json.dumps(ingredient_list, ensure_ascii=False)}
    """

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini", 
            response_format={ "type": "json_object" }, 
            messages=[
                {"role": "system", "content": "You are a helpful assistant designed to output JSON. Please output a JSON object containing a 'data' key which holds the array of mappings."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.1 
        )
        
        result_text = response.choices[0].message.content
        parsed_result = json.loads(result_text)
        
        return parsed_result.get("data", [])
        
    except Exception as e:
        print(f"\n[錯誤] LLM API 發生錯誤: {e}")
        return []

# ==========================================
# 3. 主程式流程
# ==========================================
def main():
    # --- 設定輸出路徑與建立 Timestamp 資料夾 ---
    base_out_dir = os.path.join("workspace", "src", "recipe_nutrition_unmatch", "data", "output")
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    current_out_dir = os.path.join(base_out_dir, timestamp)
    
    os.makedirs(current_out_dir, exist_ok=True)
    print(f"📂 已建立本次輸出資料夾：{current_out_dir}")

    global_cache_file = os.path.join(base_out_dir, "ingredient_mapping_latest.json") 
    run_cache_file = os.path.join(current_out_dir, "ingredient_mapping.json")        
    run_recipe_file = os.path.join(current_out_dir, "recipes_normalized.json")       

    # --- Step A: 讀取已存在的快取字典 ---
    ingredient_mapping = {}
    if os.path.exists(global_cache_file):
        with open(global_cache_file, "r", encoding="utf-8") as f:
            ingredient_mapping = json.load(f)
        print(f"🔄 已載入全域快取字典，目前包含 {len(ingredient_mapping)} 筆對應。")
    
    # --- Step B: 讀取食譜，收集所有食材名稱 ---
    with open(RECIPES_FILE, "r", encoding="utf-8") as f:
        recipes = json.load(f)
        
    unique_ingredients = set()
    # 加上 tqdm：顯示正在掃描第幾個食譜
    for recipe in tqdm(recipes, desc="📝 掃描食譜並提取食材"):
        for ingredient in recipe.get("ingredients", []):
            raw_name = ingredient.get("name_raw", ingredient.get("name", ""))
            if raw_name:
                unique_ingredients.add(raw_name)

    # --- Step C: 過濾出「尚未被正規化」的新食材 ---
    unknown_ingredients = [ing for ing in unique_ingredients if ing not in ingredient_mapping]
    print(f"📊 共有 {len(unique_ingredients)} 種獨特食材，其中 {len(unknown_ingredients)} 種需要送交 LLM 正規化。")

    # --- Step D: 批次呼叫 LLM 進行處理 ---
    BATCH_SIZE = 50 
    if unknown_ingredients:
        # 計算總批次數供 tqdm 使用
        total_batches = (len(unknown_ingredients) + BATCH_SIZE - 1) // BATCH_SIZE
        
        # 加上 tqdm：顯示 LLM 批次處理的進度
        for i in tqdm(range(0, len(unknown_ingredients), BATCH_SIZE), total=total_batches, desc="🤖 LLM 正規化處理中"):
            batch = unknown_ingredients[i:i+BATCH_SIZE]
            
            llm_results = normalize_ingredients_with_llm(batch)
            
            for item in llm_results:
                raw_name = item.get("raw")
                norm_name = item.get("normalized")
                if raw_name and norm_name:
                    ingredient_mapping[raw_name] = norm_name

            # 即時儲存快取
            with open(global_cache_file, "w", encoding="utf-8") as f:
                json.dump(ingredient_mapping, f, ensure_ascii=False, indent=2)
            with open(run_cache_file, "w", encoding="utf-8") as f:
                json.dump(ingredient_mapping, f, ensure_ascii=False, indent=2)
                
        print(f"✅ LLM 正規化完成！快取已儲存。")
    else:
        print("⚡ 所有食材皆已在字典中，跳過 LLM 處理。")

    # --- Step E: 將標準化名稱寫回原食譜結構中 ---
    # 加上 tqdm：顯示寫回食譜的進度
    for recipe in tqdm(recipes, desc="💾 將正規化名稱寫回食譜"):
        for ingredient in recipe.get("ingredients", []):
            raw_name = ingredient.get("name_raw", ingredient.get("name", ""))
            ingredient["normalized_name"] = ingredient_mapping.get(raw_name, raw_name)

    # 寫入到帶有 Timestamp 的資料夾中
    with open(run_recipe_file, "w", encoding="utf-8") as f:
        json.dump(recipes, f, ensure_ascii=False, indent=2)
    print(f"\n🎉 處理完畢！已產生最終檔案於：{run_recipe_file}")

if __name__ == "__main__":
    main()