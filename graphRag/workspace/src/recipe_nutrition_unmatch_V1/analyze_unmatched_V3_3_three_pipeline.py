"""
版本差異追蹤紀錄：
[V3_2] -> [V3_3]
1. 任務過濾邏輯優化：在建立任務清單時，會先檢查該食材是否已經有 `db_id`，有則跳過。
2. 查詢優先級調整 (Query Priority) 與情境分流：
   - 情況 1：`normalized_name` 與 `db_id` 都是 null -> 帶入食譜上下文 (recipe_name, other_ingredients)，請 LLM 推斷原始食材。
   - 情況 2：`normalized_name` 有值，但 `db_id` 是 null -> 使用 NutritionQueryTool 對 `normalized_name` 直接匹配。
3. 新增測試限制變數：使用 TEST_LIMIT 來控制處理的資料筆數，方便試跑。
"""

import sys
sys.path.insert(0, r"C:\Users\PARALELL\Desktop\code4\workspace\src")

import os
import json
import re
import threading
import concurrent.futures
from datetime import datetime
from tqdm import tqdm
from openai import OpenAI
from dotenv import load_dotenv

# 引入我們剛剛寫好的查詢小工具
from tools.query_nutrition_V4 import NutritionQueryTool

# ==========================================
# 1. 載入環境變數與 API 設定
# ==========================================
load_dotenv()

API_KEY = os.getenv("OPENAI_API_KEY")
DB_PATH = os.getenv("DB_PATH", "nutrition_data.json")
INPUT_RECIPES_PATH = os.getenv("INPUT_RECIPES_PATH", "normalized_recipes.json") 
MAX_WORKERS = int(os.getenv("MAX_WORKERS", 10))
# 🌟 新增：設定要測試的資料筆數 (0 代表處理所有需要修復的資料)
TEST_LIMIT = int(os.getenv("TEST_LIMIT", 0)) # 設為 0 代表全跑

client = OpenAI(api_key=API_KEY)
MODEL_NAME = "gpt-4.1-nano"

# 🌟 定義 Cache 檔案路徑
CACHE_FILE_PATH = os.path.join("workspace", "src", "recipe_nutrition_unmatch", "data", "llm_cache.json")

class IngredientAligner:
    def __init__(self, nutrition_tool, log_file_path, log_lock):
        self.tool = nutrition_tool
        self.log_file_path = log_file_path
        self.log_lock = log_lock
        self.names_str = "、".join(self.tool.available_names)
        
        # 🌟 載入 Cache 字典
        self.cache_lock = threading.Lock()
        self.cache = self._load_cache()
        
    def _load_cache(self):
        """讀取本地端的 Cache 檔案"""
        if os.path.exists(CACHE_FILE_PATH):
            try:
                with open(CACHE_FILE_PATH, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        # 若檔案不存在或損壞，回傳預設空結構
        return {"translation": {}, "search": {}}

    def _save_cache(self):
        """將 Cache 寫入本地端檔案 (確保多執行緒安全)"""
        with self.cache_lock:
            # 建立目錄確保路徑存在
            os.makedirs(os.path.dirname(CACHE_FILE_PATH), exist_ok=True)
            with open(CACHE_FILE_PATH, 'w', encoding='utf-8') as f:
                json.dump(self.cache, f, ensure_ascii=False, indent=4)
        
    def process_task(self, original_name, normalized_name, recipe_name, other_ingredients_str):
        matched_sample_name = None
        match_reason = "無"
        match_type = "未知"
        
        try:
            # ==========================================
            # 情況 1: normalized_name 為空 (需要食譜上下文)
            # ==========================================
            if not normalized_name:
                match_type = "上下文推斷 + 混合檢索 (情況 1)"
                translation_cache_key = f"{recipe_name}_{original_name}"
                
                # 🌟 [步驟 1: Cache 檢查] 翻譯原名
                if translation_cache_key in self.cache["translation"]:
                    inferred_name = self.cache["translation"][translation_cache_key]
                    is_cached_translation = True
                else:
                    context_prompt = f"""
                    在食譜《{recipe_name}》（其他食材包含：{other_ingredients_str}）中，有一個食材的原始名稱叫做「{original_name}」。
                    請根據這道料理的上下文與台灣的烹飪習慣，將這個食材轉換為一個「最標準、最常見的通用食材名稱」。
                    
                    【轉換規則】：
                    1. 若原名為方言、俗語或錯字（如：紅柿 -> 番茄，起士絲 -> 起司）。
                    2. 若原名已經很標準（如：香蕉、豬絞肉、鹽），請直接回傳原名即可。
                    3. 請只回傳該通用名稱字串，絕對不要包含任何其他解釋或標點符號。
                    """
                    response = client.chat.completions.create(
                        model=MODEL_NAME,
                        messages=[{"role": "user", "content": context_prompt}],
                        temperature=0.1
                    )
                    inferred_name = response.choices[0].message.content.strip()
                    is_cached_translation = False
                    
                    # 寫入 Cache
                    with self.cache_lock:
                        self.cache["translation"][translation_cache_key] = inferred_name
                    self._save_cache()

                # 🌟 [步驟 2: Cache 檢查] 混合檢索
                if inferred_name in self.cache["search"]:
                    candidates = self.cache["search"][inferred_name]
                    is_cached_search = True
                else:
                    candidates = self.tool.ask_llm_for_top_k(inferred_name, k=3, verbose=False)
                    is_cached_search = False
                    # 寫入 Cache
                    with self.cache_lock:
                        self.cache["search"][inferred_name] = candidates
                    self._save_cache()
                
                cache_status = f"(快取狀態: 翻譯 {'命中' if is_cached_translation else '未命中'}, 檢索 {'命中' if is_cached_search else '未命中'})"
                
                if candidates:
                    matched_sample_name = candidates[0].get("name")
                    match_reason = f"{cache_status} 上下文推斷通用名為「{inferred_name}」。小工具配對理由：{candidates[0].get('reason')}"
                else:
                    match_reason = f"{cache_status} 上下文推斷通用名為「{inferred_name}」，但小工具找不到相符項目。"
            
            # ==========================================
            # 情況 2: normalized_name 有值 (直接查詢資料庫)
            # ==========================================
            else:
                match_type = f"直接混合檢索 (情況 2: 依據 {normalized_name})"
                
                # 🌟 [Cache 檢查] 混合檢索
                if normalized_name in self.cache["search"]:
                    candidates = self.cache["search"][normalized_name]
                    is_cached_search = True
                else:
                    candidates = self.tool.ask_llm_for_top_k(normalized_name, k=3, verbose=False)
                    is_cached_search = False
                    # 寫入 Cache
                    with self.cache_lock:
                        self.cache["search"][normalized_name] = candidates
                    self._save_cache()
                    
                cache_status = f"(快取狀態: 檢索 {'命中' if is_cached_search else '未命中'})"

                if candidates:
                    matched_sample_name = candidates[0].get("name")
                    match_reason = f"{cache_status} 依據正規化名稱「{normalized_name}」混合檢索成功。理由：{candidates[0].get('reason')}"
                else:
                    match_reason = f"{cache_status} 使用「{normalized_name}」進行混合檢索，找不到項目。"
                    
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
        log_output = (
            f"【食譜名稱】：{recipe_name}\n"
            f"【其他食材】：{other_ingredients_str}\n"
            f"【原始食材】：{original_name} | 【正規化】：{normalized_name}\n"
            f"【處理策略】：{match_type}\n"
            f"【匹配結果】：{status_symbol} {matched_sample_name} (整合編號: {db_id})\n"
            f"【推斷理由】：{match_reason}\n"
            f"--------------------------------------------------\n"
        )
        
        with self.log_lock:
            with open(self.log_file_path, 'a', encoding='utf-8') as lf:
                lf.write(log_output)
                
        return {
            "normalized_name": matched_sample_name if matched_sample_name else normalized_name,
            "db_id": db_id,
            "reason": match_reason
        }
    
def main():
    # 建立輸出目錄
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = os.path.join("workspace", "src", "recipe_nutrition_unmatch", "data", "output", timestamp)
    os.makedirs(output_dir, exist_ok=True)
    
    output_file_path = os.path.join(output_dir, "repaired_normalized_recipes.json")
    prompt_log_path = os.path.join(output_dir, "prompt_logs.txt")
    log_lock = threading.Lock()

    # 1. 檢查檔案並初始化 NutritionQueryTool
    if not os.path.exists(INPUT_RECIPES_PATH):
        print(f"❌ 錯誤：找不到食譜檔案 {INPUT_RECIPES_PATH}")
        return
        
    print(f"正在載入營養資料庫 ({DB_PATH})...")
    nutrition_tool = NutritionQueryTool(DB_PATH)
    if not nutrition_tool.available_names:
        print("❌ 錯誤：無法載入營養資料庫。")
        return
        
    aligner = IngredientAligner(nutrition_tool, prompt_log_path, log_lock)
    
    # 2. 讀取食譜檔案
    with open(INPUT_RECIPES_PATH, 'r', encoding='utf-8') as f:
        recipes = json.load(f)
        
    # 3. 建立任務清單
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
            normalized_name = ingredient.get('normalized_name')
            
            # 取得「其他食材」供情況 1 上下文使用
            other_ingredients = [ing for ing in all_ings_list if ing != original_name]
            other_ingredients_str = ", ".join(other_ingredients)
            
            tasks.append({
                "r_idx": r_idx,
                "i_idx": i_idx,
                "original_name": str(original_name),
                "normalized_name": str(normalized_name) if normalized_name else None,
                "recipe_name": recipe_name,
                "other_ingredients_str": other_ingredients_str
            })
            
            # 若設定了 TEST_LIMIT，提早中斷任務蒐集
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
    
    # 4. 執行多執行緒處理
    if len(tasks) > 0:
        with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            # 提交任務
            futures = {
                executor.submit(
                    aligner.process_task, 
                    t["original_name"], 
                    t["normalized_name"], 
                    t["recipe_name"], 
                    t["other_ingredients_str"]
                ): t for t in tasks
            }
            
            for future in tqdm(concurrent.futures.as_completed(futures), total=len(tasks), desc="缺漏修復進度", unit="item"):
                task_info = futures[future]
                r_idx, i_idx = task_info["r_idx"], task_info["i_idx"]
                try:
                    result = future.result()
                    # 更新 recipes JSON 物件
                    if result.get("normalized_name"):
                        recipes[r_idx]['ingredients'][i_idx]['normalized_name'] = result.get('normalized_name')
                    if result.get("db_id"):
                        recipes[r_idx]['ingredients'][i_idx]['db_id'] = result.get('db_id')
                        
                except Exception as e:
                    recipes[r_idx]['ingredients'][i_idx]['error'] = str(e)

    # 5. 存檔
    with open(output_file_path, 'w', encoding='utf-8') as f:
        json.dump(recipes, f, ensure_ascii=False, indent=4)
        
    print(f"\n✅ 修復任務完成！")
    print(f"📁 補齊 db_id 後的最終檔案已儲存於：{output_file_path}")
    print(f"📄 處理紀錄 (Log) 已儲存於：{prompt_log_path}")

if __name__ == "__main__":
    main()