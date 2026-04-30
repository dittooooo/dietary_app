# C:/Users/PARALELL/AppData/Local/Programs/Python/Python312/python.exe c:/Users/PARALELL/Desktop/code4/workspace/src/recipe_nutrition_unmatch_V1_V3_2/analyze_unmatched_V3_2_three_pipeline.py

# ==========================================
# 近期修改紀錄：
# 1. 支援讀取分類過的 dict 格式 JSON 資料，自動展開分類後的食材列表。
# 2. 修改 DB_PATH 預設值為新的分類資料庫。
# 3. 修正 get_candidates 的相似度計算邏輯，將俗名以逗號切分後分別比對，避免「香蕉」等名稱因俗名過長導致相似度被拉低。
# 4. 新增 START_IDX 與 END_IDX 變數，可控制測試的食譜範圍。
# 5. 放寬 Prompt 中的嚴格比對限制，允許同義詞推斷（例如將「水」對應為「純水」）。
# 6. 優化終端機顯示資訊，清楚標示目前處理的食譜索引範圍與總數。
# 7. 修正 Prompt 縮排問題並強化配對規則，確保「水」等基礎食材能正確對應到「純水」。
# 8. 在 get_candidates 中加入常見基礎食材（油、水、鹽、糖）的語意擴展比對，解決因字數太短導致正確項被排除的問題。
# ==========================================

import os
import json
import difflib
import threading
import concurrent.futures
from datetime import datetime
from tqdm import tqdm
from openai import OpenAI
from dotenv import load_dotenv

# ==========================================
# 1. 載入環境變數與 API 設定
# ==========================================
load_dotenv()  # 自動尋找並讀取 .env 檔案

API_KEY = os.getenv("OPENAI_API_KEY")
DB_PATH = os.getenv("DB_PATH", "workspace/src/recipe_nutrition_unmatch_V1_V3_2/input/2_nutrition_data_categorized_20260422_170816.json")
INPUT_RECIPES_PATH = os.getenv("INPUT_RECIPES_PATH", r"workspace\src\recipe_nutrition_unmatch_V1_V3_2\input\recipes.json")
MAX_WORKERS = int(os.getenv("MAX_WORKERS", 10))

# ==========================================
# 測試設定
# 可透過 START_IDX 與 END_IDX 決定要處理的食譜範圍。若要處理全部，可設為 None
# 例如：START_IDX = 0, END_IDX = 10 代表處理第 0 篇到第 9 篇食譜
# ==========================================
START_IDX = 3
END_IDX = 5

client = OpenAI(api_key=API_KEY)
MODEL_NAME = "gpt-4.1-nano"

class IngredientAligner:
    def __init__(self, db_path, log_file_path, log_lock):
        self.log_file_path = log_file_path
        self.log_lock = log_lock
        
        # 確保資料庫路徑存在
        if not os.path.exists(db_path):
            raise FileNotFoundError(f"找不到資料庫檔案: {db_path}，請檢查 .env 設定。")

        with open(db_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        self.db = []
        
        # 支援原本的 list 格式以及分類過的 dict 格式
        items_to_process = []
        if isinstance(data, dict):
            for category_items in data.values():
                items_to_process.extend(category_items)
        else:
            items_to_process = data

        for item in items_to_process:
            standard_name = item.get("樣品名稱", "")
            common_names = item.get("俗名", "")
            if not isinstance(common_names, str):
                common_names = ""
            
            self.db.append({
                "id": item.get("整合編號", ""),
                "name": standard_name,
                "common_names": common_names
            })

    def _clean_query(self, query):
        prompt = f"""
        你是一位專業的食材處理助手。
        請將以下食譜中的「口語化食材名稱」萃取出「核心食材名稱」。
        請去除品牌、切法、包裝狀態與其他非核心修飾詞。
        若為常見俗名，請盡量還原為標準名。
        
        【輸入食材】：{query}
        
        請務必以 JSON 格式回傳，格式如下：
        {{"cleaned_name": "處理後的核心食材"}}
        """
        try:
            response = client.chat.completions.create(
                model=MODEL_NAME,
                response_format={"type": "json_object"},
                messages=[
                    {"role": "system", "content": "你是一個輸出 JSON 格式的食材萃取系統。"},
                    {"role": "user", "content": prompt}
                ],
                temperature=0
            )
            result = json.loads(response.choices[0].message.content)
            return result.get("cleaned_name", query)
        except Exception:
            return query

    def get_candidates(self, cleaned_query, top_k=5):
        # 對於極短的常見關鍵字進行語意擴展，增加配對成功率
        search_queries = [cleaned_query]
        if cleaned_query == "油": search_queries.append("烹調油")
        elif cleaned_query == "水": search_queries.append("純水")
        elif cleaned_query == "鹽": search_queries.append("食鹽")
        elif cleaned_query == "糖": search_queries.append("砂糖")

        scores = []
        for item in self.db:
            max_item_score = 0
            for sq in search_queries:
                score_name = difflib.SequenceMatcher(None, sq, item['name']).ratio()
                
                # 將俗名用逗號拆分，分別計算相似度並取最高者
                common_names_list = [n.strip() for n in item['common_names'].replace('，', ',').split(',')]
                score_common = 0
                for cn in common_names_list:
                    if cn:
                        cn_score = difflib.SequenceMatcher(None, sq, cn).ratio()
                        if cn_score > score_common:
                            score_common = cn_score
                
                current_max = max(score_name, score_common)
                if current_max > max_item_score:
                    max_item_score = current_max
            
            scores.append((max_item_score, item))
            
        scores.sort(key=lambda x: x[0], reverse=True)
        return [item for score, item in scores[:top_k]]

    def process_with_llm(self, original_query, recipe_name, all_ingredients_str):
        cleaned_query = self._clean_query(original_query)
        candidates = self.get_candidates(cleaned_query)
        
        candidate_list_str_for_prompt = "\n".join(
            [f"- 選項: {c['name']} (俗名: {c['common_names']}, 整合編號: {c['id']})" for c in candidates]
        )
        
        prompt = f"""你是一位專業的食品資料對照專家。
請將食譜中的食材名稱，對應到下列我從資料庫中檢索出的【候選標準名稱】。

【食譜食材】：{original_query}
【核心食材名稱】：{cleaned_query}

【候選標準名稱】：
{candidate_list_str_for_prompt}

【請務必遵守以下規則】：
1. 根據上述選項，挑選出語意最符合的單一官方標準名稱（允許同義詞、俗名或合理推斷對應）。
2. 特別注意：若食譜食材為「水」，請務必對應到候選名單中的「純水」或相關水資源項目，不可回傳 null。
3. 若選項中完全沒有任何種類相關的適合項目（例如香蕉對應到香腸），才允許讓 normalized 與 db_id 回傳 null。
4. 輸出必須是合法的 JSON 格式。

回傳格式：
{{
"raw": "{original_query}",
"cleaned_query": "{cleaned_query}",
"normalized": "選中選項的標準名稱",
"db_id": "選中選項的整合編號"
}}"""

        try:
            response = client.chat.completions.create(
                model=MODEL_NAME,
                response_format={"type": "json_object"},
                messages=[
                    {"role": "system", "content": "你是一個輸出 JSON 格式的資料對照系統。"},
                    {"role": "user", "content": prompt}
                ],
                temperature=0
            )
            result = json.loads(response.choices[0].message.content)
            normalized_name = result.get('normalized')
            db_id = result.get('db_id')
            
            final_choice_str = "無匹配 (null)"
            if normalized_name and db_id:
                for c in candidates:
                    if c['id'] == db_id:
                        final_choice_str = f"{c['name']} (俗名: {c['common_names']}, 整合編號: {c['id']})"
                        break
                        
        except Exception as e:
            result = {"raw": original_query, "normalized": None, "db_id": None, "error": str(e)}
            final_choice_str = f"發生錯誤: {str(e)}"

        # 整理 Log 格式
        candidate_list_str_for_log = "\n".join(
            [f"選項: {c['name']} (俗名: {c['common_names']}, 整合編號: {c['id']})" for c in candidates]
        )
        
        log_output = (
            f"【食譜名稱】：{recipe_name}\n"
            f"【食譜所有食材】：{all_ingredients_str}\n"
            f"【食譜食材】：{original_query}\n"
            f"【候選標準名稱】：\n\n"
            f"{candidate_list_str_for_log}\n\n"
            f"【最終選項】：{final_choice_str}\n"
            f"--------------------------------------------------\n"
        )
        
        tqdm.write(log_output)
        with self.log_lock:
            with open(self.log_file_path, 'a', encoding='utf-8') as lf:
                lf.write(log_output + "\n")

        return result

def main():
    # 建立輸出目錄
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = os.path.join("workspace", "src", "recipe_nutrition_unmatch_V1_V3_2", "output")
    os.makedirs(output_dir, exist_ok=True)
    
    output_file_path = os.path.join(output_dir, "normalized_recipes.json")
    prompt_log_path = os.path.join(output_dir, f"prompt_logs_{timestamp}.txt")

    log_lock = threading.Lock()
    aligner = IngredientAligner(DB_PATH, prompt_log_path, log_lock)
    
    # 讀取食譜檔案
    if not os.path.exists(INPUT_RECIPES_PATH):
        print(f"❌ 錯誤：找不到食譜檔案 {INPUT_RECIPES_PATH}")
        return

    with open(INPUT_RECIPES_PATH, 'r', encoding='utf-8') as f:
        recipes = json.load(f)
        
    # 套用起訖範圍過濾
    start = START_IDX if START_IDX is not None else 0
    end = END_IDX if END_IDX is not None else len(recipes)
    recipes_to_process = recipes[start:end]
        
    tasks = []
    for relative_r_idx, recipe in enumerate(recipes_to_process):
        r_idx = start + relative_r_idx
        recipe_name = recipe.get('name', '未命名食譜')
        all_ings_list = [str(ing.get('name') or ing.get('name_raw', '')) for ing in recipe.get('ingredients', [])]
        all_ingredients_str = ", ".join(all_ings_list)
        
        for i_idx, ingredient in enumerate(recipe.get('ingredients', [])):
            query = ingredient.get('name') or ingredient.get('name_raw')
            if query:
                tasks.append((r_idx, i_idx, str(query), recipe_name, all_ingredients_str))

    print(f"🚀 開始處理：食譜索引 {start} 至 {end-1} (共 {len(recipes_to_process)} 篇食譜)。")
    print(f"📦 總計提取出 {len(tasks)} 項食材，使用 {MAX_WORKERS} 個執行緒進行正規化...")
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {
            executor.submit(aligner.process_with_llm, query, r_name, all_ings): (r_idx, i_idx) 
            for r_idx, i_idx, query, r_name, all_ings in tasks
        }
        
        for future in tqdm(concurrent.futures.as_completed(futures), total=len(tasks), desc="正規化進度", unit="item"):
            r_idx, i_idx = futures[future]
            try:
                result = future.result()
                recipes[r_idx]['ingredients'][i_idx]['normalized_name'] = result.get('normalized')
                recipes[r_idx]['ingredients'][i_idx]['db_id'] = result.get('db_id')
            except Exception as e:
                recipes[r_idx]['ingredients'][i_idx]['error'] = str(e)

    with open(output_file_path, 'w', encoding='utf-8') as f:
        json.dump(recipes, f, ensure_ascii=False, indent=4)
        
    print(f"\n✅ 任務完成！結果儲存於：{output_dir}")

if __name__ == "__main__":
    main()