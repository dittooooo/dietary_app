import json
import time
from openai import OpenAI

import os
from dotenv import load_dotenv
load_dotenv()
# 初始化 OpenAI 客戶端 (請填入您的 API Key)
API_KEY = os.getenv("OPENAI_API_KEY")
client = OpenAI(api_key=API_KEY)
MODEL_NAME = "gpt-4.1-nano"


def check_ingredients_with_llm(recipe_name, ingredients):
    """
    呼叫 LLM 檢查該食譜下的食材是否合理。
    """
    # 建立食材清單字串，並處理 null/None 的情況
    ingredients_list_str = ""
    for ing in ingredients:
        raw_name = ing.get('name_raw', '未知')
        norm_name = ing.get('normalized_name')
        if not norm_name:
            norm_name = "無(空值)"
        ingredients_list_str += f"- 原始名稱: {raw_name}, 正規化名稱: {norm_name}\n"

    prompt = f"""
你是一個台灣食品與營養專家。請幫我檢查以下食譜中的「正規化名稱」是否有不合理的情況。
通常這些不合理是因為系統正規化錯誤（例如：把「水」錯誤正規化為「香水芒果」）。
如果正規化名稱為「無(空值)」，請直接將其判定為 "No"，並說明「查無對應食材」。

食譜名稱：{recipe_name}
食材對照列表：
{ingredients_list_str}

請務必以 JSON 物件 (JSON Object) 的格式回傳，且必須包含一個名為 "results" 的陣列。
陣列中的順序必須與上述食材列表完全一致 (共 {len(ingredients)} 個)。
每個元素需包含以下兩個欄位：
1. "normalized_result": 合理請填 "Yes"；不合理或非常突兀請填 "No"。
2. "normalized_result_reason": 簡短說明原因。

回傳格式範例：
{{
    "results": [
        {{"normalized_result": "Yes", "normalized_result_reason": "水餃皮可用於製作千層麵"}},
        {{"normalized_result": "No", "normalized_result_reason": "查無對應食材"}}
    ]
}}
    """

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini", 
            messages=[
                {"role": "system", "content": "你是一個輸出純 JSON 格式的助手，必須輸出包含 'results' 鍵值的 JSON Object。"},
                {"role": "user", "content": prompt}
            ],
            temperature=0.1,
            response_format={ "type": "json_object" } 
        )
        
        content = response.choices[0].message.content.strip()
        
        # 解析 JSON
        parsed_data = json.loads(content)
        
        # 提取 results 陣列
        results_array = parsed_data.get("results", [])
        return results_array
    
    except Exception as e:
        print(f"\n  -> API 呼叫或解析失敗，錯誤: {e}")
        return None

def main():
    input_file = r'C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch\data\output\20260417_110724\repaired_normalized_recipes.json'

    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, "output")
    os.makedirs(output_dir, exist_ok=True)
    output_file = os.path.join(output_dir, "checked_normalized_recipes.json")

    # 1. 讀取原始 JSON
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            recipes = json.load(f)
    except FileNotFoundError:
        print(f"找不到檔案 {input_file}，請確認路徑是否正確。")
        return

    print(f"總共載入 {len(recipes)} 筆食譜，開始進行 LLM 檢查...\n")

    # 2. 逐一檢查食譜
    for i, recipe in enumerate(recipes):
        recipe_name = recipe.get("name", "未知食譜")
        ingredients = recipe.get("ingredients", [])
        
        if not ingredients:
            continue
            
        print(f"[{i+1}/{len(recipes)}] 正在檢查食譜: {recipe_name} ...", end=" ")
        
        llm_results = check_ingredients_with_llm(recipe_name, ingredients)
        
        # 3. 檢查 LLM 回傳結果是否與食材數量一致
        if llm_results is not None and len(llm_results) == len(ingredients):
            for idx, ing in enumerate(ingredients):
                ing["normalized_result"] = llm_results[idx].get("normalized_result", "Error")
                ing["normalized_result_reason"] = llm_results[idx].get("normalized_result_reason", "解析失敗")
            print("檢查完畢")
        else:
            actual_len = len(llm_results) if llm_results is not None else 0
            print(f"失敗 (警告：預期 {len(ingredients)} 筆，但 LLM 回傳 {actual_len} 筆，將標記為 Error)")
            
            for ing in ingredients:
                ing["normalized_result"] = "Error"
                ing["normalized_result_reason"] = "LLM 回傳數量不符"
        
        # 避免觸發 API Rate Limit，可適當暫停
        time.sleep(0.5)

    # 4. 將結果存入新的 JSON 檔案
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(recipes, f, ensure_ascii=False, indent=4)

    print(f"\n檢查完成！結果已儲存至 {output_file}")
    
    # 5. 只匯出有問題 (No 或 Error) 的資料
    problematic_recipes = []
    for recipe in recipes:
        bad_ingredients = [
            ing for ing in recipe.get("ingredients", []) 
            if ing.get("normalized_result") in ["No", "Error"]
        ]
        if bad_ingredients:
            problematic_recipes.append({
                "recipe_id": recipe.get("recipe_id"),
                "name": recipe.get("name"),
                "bad_ingredients": bad_ingredients
            })
            
    with open('problematic_ingredients.json', 'w', encoding='utf-8') as f:
        json.dump(problematic_recipes, f, ensure_ascii=False, indent=4)
        
    print(f"有問題的食材已獨立抽出來儲存至 problematic_ingredients.json")

    # 6. 找出包含 db_id 為 null 的食譜，並萃取其 recipe_id
    null_db_id_recipes = []
    for recipe in recipes:
        has_null_db = any(ing.get("db_id") is None for ing in recipe.get("ingredients", []))
        if has_null_db and recipe.get("recipe_id"):
            null_db_id_recipes.append(recipe.get("recipe_id"))
            
    with open('failed_null_db_id_recipes.json', 'w', encoding='utf-8') as f:
        json.dump(null_db_id_recipes, f, ensure_ascii=False, indent=4)
        
    print(f"含有 db_id 為 null 的失敗 recipe_id 已儲存至 failed_null_db_id_recipes.json，共 {len(null_db_id_recipes)} 筆")

if __name__ == "__main__":
    main()

