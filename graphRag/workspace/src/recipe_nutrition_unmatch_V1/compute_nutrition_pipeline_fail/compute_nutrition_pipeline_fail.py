"""
完整營養學換算流水線 (Compute Nutrition Pipeline)
將未對應完成的 recipes.json，進一步結合:
1. DB 對齊 + 信心度門檻 (低於 60 分則拒絕)。
2. 若拒絕，則啟動 OnlineNutritionSearchTool 聯網擷取 100g 數據，動態寫入 DB 並快照備份。
3. 採用 AmountEstimator 將原始用量 (例如 12片) 換算為預估公克 (grams)。
4. 乘積換算出該食材在此食譜中的真實熱量與營養素。
最後匯出 recipes_per_serving_v4.json
"""

import os
import json
import threading
import concurrent.futures
from datetime import datetime
from tqdm import tqdm
from dotenv import load_dotenv

import sys
base_dir = os.path.dirname(os.path.abspath(__file__))
# 確保找得到 tools
tools_path = os.path.join(os.path.dirname(base_dir), "tools")
if tools_path not in sys.path:
    sys.path.insert(0, os.path.dirname(base_dir))

from tools.query_nutrition_V6 import NutritionQueryToolContextual
from tools.online_nutrition_search import OnlineNutritionSearchTool
from tools.amount_estimator import AmountEstimator

load_dotenv()

class FullNutritionPipeline:
    def __init__(self):
        self.max_workers = int(os.getenv("MAX_WORKERS", 0))
        self.test_limit = int(os.getenv("TEST_LIMIT", 40)) # 0 表示不限制
        
        # 路徑設定
        self.input_recipes = os.path.join(base_dir, "data", "input", "recipes.json")
        self.db_file = os.path.join(base_dir, "data", "input", "nutrition_data.json")
        self.cache_file = os.path.join(base_dir, "data", "pipeline_v4_cache.json")
        
        # 目錄建立
        self.timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.output_dir = os.path.join(base_dir, "data", "output", f"V4_{self.timestamp}")
        os.makedirs(self.output_dir, exist_ok=True)
        self.output_file = os.path.join(self.output_dir, "recipes_per_serving_v4.json")
        self.log_file = os.path.join(self.output_dir, "pipeline_logs.txt")
        self.log_lock = threading.Lock()
        
        # 核心工具初始化
        print(f"正在載入全域營養資料庫 ({self.db_file})...")
        self.nutrition_db_tool = NutritionQueryToolContextual(self.db_file)
        self.online_search_tool = OnlineNutritionSearchTool()
        self.amount_estimator = AmountEstimator()
        
        self.db_lock = threading.Lock()
        
        self.cache_lock = threading.Lock()
        self.cache = self._load_cache()
        
    def _load_cache(self):
        if os.path.exists(self.cache_file):
            try:
                with open(self.cache_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def _save_cache(self):
        with self.cache_lock:
            with open(self.cache_file, 'w', encoding='utf-8') as f:
                json.dump(self.cache, f, ensure_ascii=False, indent=4)
                
    def _append_log(self, text):
        with self.log_lock:
            with open(self.log_file, 'a', encoding='utf-8') as f:
                f.write(text + "\n")
                
    def _register_new_web_ingredient(self, search_data, original_name):
        """
        將線上搜尋到的資料擴充進 DB 中，並配置 WEB_XXX 編號。
        """
        with self.db_lock:
            # 尋找現有的 WEB 編號最大值
            web_items = [v for k, v in self.nutrition_db_tool.db.items() if v.get("整合編號", "").startswith("WEB_")]
            max_num = 0
            for item in web_items:
                num_str = item["整合編號"].replace("WEB_", "")
                if num_str.isdigit():
                    max_num = max(max_num, int(num_str))
                    
            new_id = f"WEB_{max_num + 1:03d}"
            db_name = search_data.get("name", original_name)
            
            new_entry = {
                "整合編號": new_id,
                "食品分類": "網路搜尋資料",
                "樣品名稱": db_name,
                "內容物描述": f"透過 GPT 聯網搜尋之食材，原始詢問名稱: {original_name}",
                "俗名": original_name,
                "熱量(kcal)": search_data.get("熱量(kcal)", 0.0),
                "水分(g)": 0.0,
                "粗蛋白(g)": search_data.get("粗蛋白(g)", 0.0),
                "粗脂肪(g)": search_data.get("粗脂肪(g)", 0.0),
                "總碳水化合物(g)": search_data.get("總碳水化合物(g)", 0.0),
                "鈉(mg)": search_data.get("鈉(mg)", 0.0)
            }
            
            # 更新記憶體中的 DB 與 mapping
            if db_name not in self.nutrition_db_tool.db:
                self.nutrition_db_tool.db[db_name] = new_entry
                self.nutrition_db_tool.available_names.append(db_name)
                self.nutrition_db_tool.synonym_mapping[original_name] = db_name
            
            # 載入現存檔案並追加
            with open(self.db_file, 'r', encoding='utf-8') as f:
                full_db = json.load(f)
            
            full_db.append(new_entry)
            
            # 備份 (不覆寫原檔)
            backup_db_file = f"{self.db_file}_{self.timestamp}"
            with open(backup_db_file, 'w', encoding='utf-8') as f:
                json.dump(full_db, f, ensure_ascii=False, indent=4)
                
            return new_entry

    def process_item(self, recipe_name, ingredient_info, other_ingredients_str):
        original_name = ingredient_info.get('name') or ingredient_info.get('name_raw', '未知食材')
        amount_raw = ingredient_info.get('amount_raw', '')
        
        cache_key = f"{recipe_name}:::{original_name}:::{amount_raw}"
        
        if cache_key in self.cache:
            return self.cache[cache_key]
            
        final_db_item = None
        match_source = "本地資料庫"
        reasoning = ""
        
        # 1. 執行本地 DB 推理 (含信心度)
        match_result = self.nutrition_db_tool.ask_llm_for_best_match(
            target_ingredient=original_name,
            recipe_name=recipe_name,
            other_ingredients=other_ingredients_str,
            verbose=False
        )
        
        db_name = match_result.get("name")
        confidence = match_result.get("confidence", 0)
        reasoning = match_result.get("reason", "")
        
        # 2. 如果信心 < 60 或是完全沒對到 => 啟動聯網
        if not db_name or confidence < 60:
            match_source = "🌐 聯網動態搜尋 (原信心不足)"
            search_data = self.online_search_tool.search_nutrition(original_name, recipe_name, verbose=False)
            
            if search_data:
                # 動態加入 DB
                final_db_item = self._register_new_web_ingredient(search_data, original_name)
                db_name = final_db_item["樣品名稱"]
                reasoning = f"本地庫無合適選項(信心:{confidence})，已成功透過網路爬蟲補齊 100g 營養數據。"
            else:
                reasoning = f"本地庫無合適選項(信心:{confidence})，且網路搜尋失敗。"
        else:
            # 本地成功
            final_db_item = self.nutrition_db_tool.get_nutrition_info(db_name)
            
        # 3. 如果成功取得 DB 項目 (不論是來自本地還是聯網)，進行重量換算
        final_grams = 0.0
        calculated_nutrition = {}
        
        if final_db_item:
            final_grams = self.amount_estimator.estimate_grams(
                recipe_name, 
                original_name, 
                amount_raw, 
                db_name=db_name, 
                verbose=False
            )
            
            # 4. 根據 100g 基準計算
            ratio = final_grams / 100.0 if final_grams > 0 else 0
            
            calculated_nutrition = {
                "熱量(kcal)": round(float(final_db_item.get("熱量(kcal)") or 0) * ratio, 2),
                "粗蛋白(g)": round(float(final_db_item.get("粗蛋白(g)") or 0) * ratio, 2),
                "粗脂肪(g)": round(float(final_db_item.get("粗脂肪(g)") or 0) * ratio, 2),
                "總碳水化合物(g)": round(float(final_db_item.get("總碳水化合物(g)") or 0) * ratio, 2),
                "鈉(mg)": round(float(final_db_item.get("鈉(mg)") or 0) * ratio, 2)
            }
            
        # 產出該 Ingredient Object 的更新 dict
        result = {
            "normalized_name": final_db_item.get("樣品名稱") if final_db_item else None,
            "db_id": final_db_item.get("整合編號") if final_db_item else None,
            "estimated_grams": final_grams,
            "per_serving_nutrition": calculated_nutrition,
            "pipeline_log": f"[{match_source}] {reasoning}"
        }
        
        with self.cache_lock:
            self.cache[cache_key] = result
        self._save_cache()
        
        # 紀錄 Log
        log_str = (
            f"【食譜】：{recipe_name}\n"
            f"【原始食材】：{original_name} ({amount_raw})\n"
            f"【處理來源】：{match_source}\n"
            f"【評估公克】：{final_grams}g\n"
            f"【匹配名稱】：{result['normalized_name']} (整合編號: {result.get('db_id')})\n"
            f"【推算營養】：{calculated_nutrition}\n"
            f"--------------------------------------------------"
        )
        self._append_log(log_str)
        
        return result

    def run(self):
        print("正在讀取原始食譜檔案...")
        with open(self.input_recipes, 'r', encoding='utf-8') as f:
            recipes = json.load(f)
            
        tasks = []
        for r_idx, recipe in enumerate(recipes):
            recipe_name = recipe.get('name', '未命名食譜')
            all_names = [str(ing.get('name') or ing.get('name_raw', '')) for ing in recipe.get('ingredients', [])]
            for i_idx, ingredient in enumerate(recipe.get('ingredients', [])):
                original_name = ingredient.get('name') or ingredient.get('name_raw', '未知')
                other_ingredients = [n for n in all_names if n != original_name]
                
                tasks.append({
                    "r_idx": r_idx,
                    "i_idx": i_idx,
                    "recipe_name": recipe_name,
                    "ingredient_info": ingredient,
                    "other_ingredients_str": ", ".join(other_ingredients)
                })
                
                if self.test_limit > 0 and len(tasks) >= self.test_limit:
                    break
            if self.test_limit > 0 and len(tasks) >= self.test_limit:
                break
                
        print(f"🚀 開始流水線處理 (採循序處理模式，共 {len(tasks)} 項食材)")
        
        # 使用 tqdm 顯示進度
        for task in tqdm(tasks, desc="完整換算流水線"):
            r_idx, i_idx = task["r_idx"], task["i_idx"]
            recipe_name = task["recipe_name"]
            ingredient_info = task["ingredient_info"]
            others = task["other_ingredients_str"]
            
            try:
                # 執行處理
                result = self.process_item(recipe_name, ingredient_info, others)
                
                # 將計算結果回寫至 recipes
                ing_ref = recipes[r_idx]['ingredients'][i_idx]
                ing_ref['normalized_name'] = result.get('normalized_name')
                ing_ref['db_id'] = result.get('db_id')
                ing_ref['estimated_grams'] = result.get('estimated_grams')
                ing_ref['per_serving_nutrition'] = result.get('per_serving_nutrition')
                ing_ref['pipeline_log'] = result.get('pipeline_log')
                
            except Exception as e:
                # 如果發生技術錯誤 (API 報錯等)，記錄在檔案中但不存入 Cache
                error_msg = f"技術性故障: {str(e)}"
                recipes[r_idx]['ingredients'][i_idx]['pipeline_error'] = error_msg
                log_str = (
                    f"❌ 【技術錯誤】食譜：{recipe_name} | 食材：{ingredient_info.get('name_raw')} \n"
                    f"錯誤詳情：{error_msg}\n"
                    f"--------------------------------------------------"
                )
                self._append_log(log_str)

        with open(self.output_file, 'w', encoding='utf-8') as f:
            json.dump(recipes, f, ensure_ascii=False, indent=4)
            
        print(f"\n✅ 營養學換算流水線執行完成！")
        print(f"📁 最終檔案已儲存於：{self.output_file}")
        print(f"📄 處理紀錄存放於：{self.log_file}")


if __name__ == "__main__":
    pipeline = FullNutritionPipeline()
    pipeline.run()
