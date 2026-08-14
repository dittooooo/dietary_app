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
DB_PATH = os.getenv("DB_PATH", "nutrition_data.json")
INPUT_RECIPES_PATH = os.getenv("INPUT_RECIPES_PATH", "recipes.json")
MAX_WORKERS = int(os.getenv("MAX_WORKERS", 10))

client = OpenAI(api_key=API_KEY)
MODEL_NAME = "gpt-4o-mini"

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
        for item in data:
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
        scores = []
        for item in self.db:
            score_name = difflib.SequenceMatcher(None, cleaned_query, item['name']).ratio()
            score_common = difflib.SequenceMatcher(None, cleaned_query, item['common_names']).ratio()
            max_score = max(score_name, score_common)
            scores.append((max_score, item))
            
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
1. 嚴格根據上述選項，挑選出最符合的一個。
2. 若選項中都沒有適合的，請讓 normalized 與 db_id 回傳 null。
3. 輸出必須是合法的 JSON 格式。

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
    output_dir = os.path.join("workspace", "src", "recipe_nutrition_unmatch", "data", "output", timestamp)
    os.makedirs(output_dir, exist_ok=True)
    
    output_file_path = os.path.join(output_dir, "normalized_recipes.json")
    prompt_log_path = os.path.join(output_dir, "prompt_logs.txt")

    log_lock = threading.Lock()
    aligner = IngredientAligner(DB_PATH, prompt_log_path, log_lock)
    
    # 讀取食譜檔案
    if not os.path.exists(INPUT_RECIPES_PATH):
        print(f"❌ 錯誤：找不到食譜檔案 {INPUT_RECIPES_PATH}")
        return

    with open(INPUT_RECIPES_PATH, 'r', encoding='utf-8') as f:
        recipes = json.load(f)
        
    tasks = []
    for r_idx, recipe in enumerate(recipes):
        recipe_name = recipe.get('name', '未命名食譜')
        all_ings_list = [str(ing.get('name') or ing.get('name_raw', '')) for ing in recipe.get('ingredients', [])]
        all_ingredients_str = ", ".join(all_ings_list)
        
        for i_idx, ingredient in enumerate(recipe.get('ingredients', [])):
            query = ingredient.get('name') or ingredient.get('name_raw')
            if query:
                tasks.append((r_idx, i_idx, str(query), recipe_name, all_ingredients_str))

    print(f"🚀 開始處理：{len(tasks)} 項食材，使用 {MAX_WORKERS} 個執行緒。")
    
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