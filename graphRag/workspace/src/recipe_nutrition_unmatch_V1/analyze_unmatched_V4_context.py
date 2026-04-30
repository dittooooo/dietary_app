"""
版本差異追蹤紀錄：
[V4]
1. 採用 V5 版全域上下文推理 (Full Context Contextual Alignment)，棄用原有的僵硬查詢機制。
2. 針對 `recipes.json` 中沒有 `db_id` 的食材，合併食譜名稱與其他食材的上下文，
   將 2180 筆營養資料庫選項全數交由 LLM 推論最適合的單一選項（不再寧缺勿濫，而是盡量找語意/功能最相近或 null）。
3. 採用新的快取金鑰結構 `(RecipeName_OriginalName)`。
"""

import sys
sys.path.insert(0, r"C:\Users\PARALELL\Desktop\code4\workspace\src")

import os
import json
import threading
import concurrent.futures
from datetime import datetime
from tqdm import tqdm
from dotenv import load_dotenv

from tools.query_nutrition_V5 import NutritionQueryToolContextual

load_dotenv()

DB_PATH = os.getenv("DB_PATH", "nutrition_data.json")
# 指定要處理的原始資料來源
INPUT_RECIPES_PATH = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch\data\input\recipes.json"
MAX_WORKERS = int(os.getenv("MAX_WORKERS", 10))
TEST_LIMIT = int(os.getenv("TEST_LIMIT", 30)) # 全量執行

base_dir = os.path.dirname(os.path.abspath(__file__))
CACHE_FILE_PATH = os.path.join(base_dir, "data", "v4_context_cache.json")

class FullContextIngredientAligner:
    def __init__(self, nutrition_tool, log_file_path, log_lock):
        self.tool = nutrition_tool
        self.log_file_path = log_file_path
        self.log_lock = log_lock
        
        self.cache_lock = threading.Lock()
        self.cache = self._load_cache()
        
    def _load_cache(self):
        if os.path.exists(CACHE_FILE_PATH):
            try:
                with open(CACHE_FILE_PATH, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def _save_cache(self):
        with self.cache_lock:
            os.makedirs(os.path.dirname(CACHE_FILE_PATH), exist_ok=True)
            with open(CACHE_FILE_PATH, 'w', encoding='utf-8') as f:
                json.dump(self.cache, f, ensure_ascii=False, indent=4)
        
    def process_task(self, original_name, recipe_name, other_ingredients_str):
        matched_sample_name = None
        match_reason = ""
        is_cached = False
        
        cache_key = f"{recipe_name}:::{original_name}"
        
        try:
            if cache_key in self.cache:
                result = self.cache[cache_key]
                is_cached = True
            else:
                result = self.tool.ask_llm_for_best_match(
                    target_ingredient=original_name,
                    recipe_name=recipe_name,
                    other_ingredients=other_ingredients_str,
                    verbose=False
                )
                with self.cache_lock:
                    self.cache[cache_key] = result
                self._save_cache()
                
            matched_sample_name = result.get("name")
            match_reason = result.get("reason", "")
            
        except Exception as e:
            match_reason = f"發生錯誤: {str(e)}"
            
        # 轉換為 db_id
        db_id = None
        if matched_sample_name:
            db_info = self.tool.get_nutrition_info(matched_sample_name)
            if db_info:
                db_id = db_info.get("整合編號")

        # 整理並寫入 Log
        status_symbol = "✅" if db_id else "❌"
        cache_flag = "[快取]" if is_cached else "[API]"
        log_output = (
            f"【食譜名稱】：{recipe_name}\n"
            f"【其他食材】：{other_ingredients_str}\n"
            f"【原始食材】：{original_name}\n"
            f"【處理來源】：{cache_flag}\n"
            f"【匹配結果】：{status_symbol} {matched_sample_name} (整合編號: {db_id})\n"
            f"【推斷理由】：{match_reason}\n"
            f"--------------------------------------------------\n"
        )
        
        with self.log_lock:
            with open(self.log_file_path, 'a', encoding='utf-8') as lf:
                lf.write(log_output)
                
        return {
            "normalized_name": matched_sample_name,
            "db_id": db_id,
            "reason": match_reason
        }
    
def main():
    # 建立輸出目錄
    base_dir = os.path.dirname(os.path.abspath(__file__))
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = os.path.join(base_dir, "data", "output", f"V4_{timestamp}")
    os.makedirs(output_dir, exist_ok=True)
    
    output_file_path = os.path.join(output_dir, "repaired_normalized_recipes.json")
    prompt_log_path = os.path.join(output_dir, "v4_prompt_logs.txt")
    log_lock = threading.Lock()

    if not os.path.exists(INPUT_RECIPES_PATH):
        print(f"❌ 錯誤：找不到食譜檔案 {INPUT_RECIPES_PATH}")
        return
        
    db_file_path = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch\data\input\nutrition_data.json"
    print(f"正在載入全域營養資料庫 ({db_file_path})...")
    nutrition_tool = NutritionQueryToolContextual(db_file_path)
    if not nutrition_tool.available_names:
        print("❌ 錯誤：無法載入全域營養資料庫。")
        return
        
    aligner = FullContextIngredientAligner(nutrition_tool, prompt_log_path, log_lock)
    
    print("正在讀取原始食譜檔案...")
    with open(INPUT_RECIPES_PATH, 'r', encoding='utf-8') as f:
        recipes = json.load(f)
        
    tasks = []
    skipped_count = 0
    
    for r_idx, recipe in enumerate(recipes):
        recipe_name = recipe.get('name', '未命名食譜')
        all_ings_list = [str(ing.get('name') or ing.get('name_raw', '')) for ing in recipe.get('ingredients', [])]
        
        for i_idx, ingredient in enumerate(recipe.get('ingredients', [])):
            if ingredient.get('db_id'):
                skipped_count += 1
                continue
            
            original_name = ingredient.get('name') or ingredient.get('name_raw', '未知食材')
            
            # 推斷上下文
            other_ingredients = [ing for ing in all_ings_list if ing != original_name]
            other_ingredients_str = ", ".join(other_ingredients)
            
            tasks.append({
                "r_idx": r_idx,
                "i_idx": i_idx,
                "original_name": str(original_name),
                "recipe_name": recipe_name,
                "other_ingredients_str": other_ingredients_str
            })
            
            if TEST_LIMIT > 0 and len(tasks) >= TEST_LIMIT:
                break
        
        if TEST_LIMIT > 0 and len(tasks) >= TEST_LIMIT:
            break

    print(f"✅ 資料庫載入完成！")
    print(f"🚀 掃描完畢：跳過 {skipped_count} 項已具備 db_id 的食材。")
    if TEST_LIMIT > 0:
        print(f"⚠️  [測試模式啟動]：限制只處理前 {TEST_LIMIT} 筆缺失資料。")
    else:
        print(f"🚀 開始處理：剩下 {len(tasks)} 項缺失 db_id 的食材。")
        
    print(f"⚙️  使用 {MAX_WORKERS} 個執行緒進行補救中...\n")
    
    if len(tasks) > 0:
        with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            futures = {
                executor.submit(
                    aligner.process_task, 
                    t["original_name"], 
                    t["recipe_name"], 
                    t["other_ingredients_str"]
                ): t for t in tasks
            }
            
            for future in tqdm(concurrent.futures.as_completed(futures), total=len(tasks), desc="V4 即時上下文推斷", unit="item"):
                task_info = futures[future]
                r_idx, i_idx = task_info["r_idx"], task_info["i_idx"]
                try:
                    result = future.result()
                    # 回寫更新 recipes JSON 物件
                    if result.get("normalized_name"):
                        recipes[r_idx]['ingredients'][i_idx]['normalized_name'] = result.get('normalized_name')
                    else:
                        recipes[r_idx]['ingredients'][i_idx]['normalized_name'] = None
                        
                    if result.get("db_id"):
                        recipes[r_idx]['ingredients'][i_idx]['db_id'] = result.get('db_id')
                    else:
                        recipes[r_idx]['ingredients'][i_idx]['db_id'] = None
                        
                except Exception as e:
                    recipes[r_idx]['ingredients'][i_idx]['error'] = str(e)

    with open(output_file_path, 'w', encoding='utf-8') as f:
        json.dump(recipes, f, ensure_ascii=False, indent=4)
        
    print(f"\n✅ V4 上下文修復網路完成！")
    print(f"📁 補齊/映射後的最終檔案已儲存於：{output_file_path}")
    print(f"📄 處理紀錄 (Log) 已儲存於：{prompt_log_path}")

if __name__ == "__main__":
    main()
