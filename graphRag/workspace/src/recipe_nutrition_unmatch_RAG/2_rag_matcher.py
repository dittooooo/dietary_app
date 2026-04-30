import json
import os
import time
from typing import Dict, List, Optional
from datetime import datetime
from dotenv import load_dotenv
import chromadb
from sentence_transformers import SentenceTransformer
from tqdm import tqdm
from openai import OpenAI

load_dotenv()

# --- Config ---
RECIPES_PATH = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\recipes.json"
OUTPUT_DIR = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\output"
CACHE_PATH = "data/output/cache.json"
CHROMA_DB_DIR = os.getenv("CHROMA_DB_DIR", "chroma_db")
COLLECTION_NAME = "nutrition_collection"
EMBEDDING_MODEL_NAME = os.getenv("EMBEDDING_MODEL_NAME", "paraphrase-multilingual-MiniLM-L12-v2")

# 測試範圍與快取設定 (None 表示不限制)
START_IDX = 0       # 從第幾個食譜開始
END_IDX = 2         # 到第幾個食譜結束 (不包含)
CLEAR_CACHE = True  # 是否在啟動時清除快取

API_KEY = os.getenv("OPENAI_API_KEY", "your_api_key_here")
BASE_URL = os.getenv("OPENAI_BASE_URL") # 預設 None (OpenAI 官方)，若使用 Ollama 會有值
MODEL_NAME = os.getenv("LLM_MODEL", "gpt-4o-mini")

# 初始化 OpenAI Client
client_kwargs = {"api_key": API_KEY}
if BASE_URL:
    client_kwargs["base_url"] = BASE_URL
client = OpenAI(**client_kwargs)

def load_json(filepath: str) -> object:
    if not os.path.exists(filepath):
        return None
    with open(filepath, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_json(filepath: str, data: object):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

class RAGMatcher:
    def __init__(self):
        print(f"🧠 載入 Embedding 模型 ({EMBEDDING_MODEL_NAME})...")
        self.embedder = SentenceTransformer(EMBEDDING_MODEL_NAME)
        
        print(f"💾 連接 ChromaDB ({CHROMA_DB_DIR})...")
        if not os.path.exists(CHROMA_DB_DIR):
            raise FileNotFoundError(f"找不到 ChromaDB 資料夾: {CHROMA_DB_DIR}，請先執行 1_build_vector_db.py")
            
        self.chroma_client = chromadb.PersistentClient(path=CHROMA_DB_DIR)
        self.collection = self.chroma_client.get_collection(name=COLLECTION_NAME)
        
        self.cache = load_json(CACHE_PATH) or {}
        self.is_ollama = BASE_URL is not None and "localhost" in BASE_URL

    def save_cache(self):
        save_json(CACHE_PATH, self.cache)

    def expand_query(self, ingredient_name: str) -> str:
        prompt = f"""
你是一個營養學與烹飪助理。
使用者輸入的食材名稱為：「{ingredient_name}」。
請給出 3 個該食材在台灣營養資料庫中「可能使用的正式學名或同義詞」，或其所屬的核心材料。
（例如：輸入「披薩起士絲」，輸出「起司,乾酪,乳酪」；輸入「泡打粉」，輸出「泡打粉,酵母粉,膨脹劑」）
請直接回傳這 3 個詞，以逗號分隔，不要有任何多餘的解釋或標點符號。
"""
        messages = [{"role": "user", "content": prompt}]
        try:
            response = client.chat.completions.create(
                model=MODEL_NAME,
                messages=messages,
                temperature=0.3
            )
            expansion = response.choices[0].message.content.strip()
            # 將原字串與擴展字串結合，提高檢索豐富度
            return f"{ingredient_name}, {expansion}"
        except Exception as e:
            print(f"Query Expansion 錯誤: {e}")
            return ingredient_name

    def retrieve_top_k(self, query: str, k: int = 20) -> List[Dict]:
        query_embedding = self.embedder.encode([query]).tolist()
        results = self.collection.query(
            query_embeddings=query_embedding,
            n_results=k
        )
        
        candidates = []
        if results and results["documents"] and results["documents"][0]:
            for i in range(len(results["documents"][0])):
                candidates.append({
                    "text": results["documents"][0][i],
                    "metadata": results["metadatas"][0][i],
                    "distance": results["distances"][0][i] if "distances" in results else None
                })
        return candidates

    def ask_llm(self, target_ingredient: str, candidates: List[Dict]) -> str:
        candidates_str = ""
        for idx, c in enumerate(candidates):
            candidates_str += f"{idx+1}. {c['text']} (樣品名稱: {c['metadata']['樣品名稱']})\n"
            
        prompt = f"""
你是一個專業的營養學與資料庫配對助手。
你的任務是從以下【候選清單】中，幫我選出「最符合」目標食材的項目。

【目標食材】：{target_ingredient}

【候選清單】：
{candidates_str}

【嚴格規則】：
1. 你「必須」從候選清單中挑選出最適合的一個，或判斷為找不到。
2. 請回傳 JSON 格式，包含以下欄位：
   - "index": 選中的項目編號（數字，例如 1 或 2），若無合理對應請給 null。
   - "reason": 你的挑選理由或判斷依據。若是找不到，請說明失敗原因（例如：候選清單皆為加工食品，不符合天然食材需求）。
3. 發揮常識與烹飪相似性：即使清單中沒有一模一樣的原料，你也必須找一個烹飪功能、營養成分最接近的「替代品」。
4. 絕對不可回傳額外的對話或解釋，只回傳純 JSON 格式！
"""
        
        messages = [
            {"role": "system", "content": "You are a helpful culinary AI. Output only a JSON object with 'index' and 'reason'."},
            {"role": "user", "content": prompt}
        ]
        
        try:
            response = client.chat.completions.create(
                model=MODEL_NAME,
                messages=messages,
                temperature=0.0,
                response_format={"type": "json_object"}
            )
            result_text = response.choices[0].message.content.strip()
            data = json.loads(result_text)
            
            index_val = data.get("index")
            reason = data.get("reason", "")
            
            if index_val is None:
                return {"name": None, "db_id": None, "reason": reason}
            
            try:
                idx = int(index_val) - 1
                if 0 <= idx < len(candidates):
                    meta = candidates[idx]['metadata']
                    return {
                        "name": meta['樣品名稱'],
                        "db_id": meta['整合編號'],
                        "reason": reason
                    }
            except (ValueError, TypeError):
                pass
            
            return {"name": None, "db_id": None, "reason": reason}
        except Exception as e:
            print(f"LLM 錯誤: {e}")
            return {"name": None, "db_id": None, "reason": f"系統錯誤: {str(e)}"}

    def process_ingredient(self, ingredient_name: str) -> Optional[str]:
        if not ingredient_name:
            return None
            
        if ingredient_name in self.cache:
            return self.cache[ingredient_name]
            
        # 1. 查詢擴展 (Query Expansion)
        expanded_query = self.expand_query(ingredient_name)
            
        # 2. 向量檢索 (傳入擴展後的字串)
        candidates = self.retrieve_top_k(expanded_query, k=20)
        if not candidates:
            return None
            
        # 3. LLM 最終決斷
        match_result = self.ask_llm(ingredient_name, candidates)
        
        if not match_result["name"]:
            print(f"\n⚠️ 配對失敗: 「{ingredient_name}」 (原因: {match_result['reason']})")
            
        self.cache[ingredient_name] = match_result
        return match_result

def main():
    print("🚀 啟動 RAG 食譜成份配對系統...")
    
    if CLEAR_CACHE and os.path.exists(CACHE_PATH):
        try:
            os.remove(CACHE_PATH)
            print(f"🧹 已清除快取檔案: {CACHE_PATH}")
        except Exception as e:
            print(f"⚠️ 無法清除快取: {e}")
            
    recipes = load_json(RECIPES_PATH)
    if not recipes:
        print(f"❌ 找不到食譜檔: {RECIPES_PATH}")
        return
        
    if recipes:
        # 根據 START_IDX 和 END_IDX 進行切片
        start = START_IDX if START_IDX is not None else 0
        end = END_IDX if END_IDX is not None else len(recipes)
        recipes = recipes[start:end]
        print(f"📌 正在處理食譜範圍: {start} 到 {end} (共 {len(recipes)} 個食譜)")

    try:
        matcher = RAGMatcher()
    except Exception as e:
        print(f"❌ 初始化失敗: {e}")
        return

    # 展開所有需要處理的食材以供 tqdm 計算
    all_ingredients = []
    for recipe in recipes:
        for ing in recipe.get("ingredients", []):
            ing_name = ing.get("name") or ing.get("name_raw")
            if ing_name:
                all_ingredients.append(ing)

    print(f"📋 共找到 {len(all_ingredients)} 個食材項目需要配對。")
    
    matched_count = 0
    save_counter = 0
    
    for ing in tqdm(all_ingredients, desc="配對進度"):
        ing_name = ing.get("name") or ing.get("name_raw")
        match_info = matcher.process_ingredient(ing_name)
        
        if match_info["name"]:
            ing["營養成份_對應名稱"] = match_info["name"]
            ing["db_id"] = match_info["db_id"]
            ing["配對原因"] = match_info["reason"]
            ing["配對失敗原因"] = None
            matched_count += 1
        else:
            ing["營養成份_對應名稱"] = None
            ing["db_id"] = None
            ing["配對原因"] = None
            ing["配對失敗原因"] = match_info["reason"]
            
        save_counter += 1
        # 每處理 50 個食材存一次 cache，避免意外中斷遺失
        if save_counter % 50 == 0:
            matcher.save_cache()

    # 最後儲存 cache
    matcher.save_cache()
    
    # 儲存結果
    run_timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = os.path.join(OUTPUT_DIR, run_timestamp)
    os.makedirs(run_dir, exist_ok=True)
    
    file_timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    range_str = f"_idx{START_IDX}_to{END_IDX}" if (START_IDX is not None or END_IDX is not None) else ""
    output_filename = f"recipes_rag_enriched_{file_timestamp}{range_str}.json"
    output_filepath = os.path.join(run_dir, output_filename)
    
    save_json(output_filepath, recipes)
    
    print("\n" + "="*40)
    print("🎉 處理完成！")
    print(f"✅ 總處理食材: {len(all_ingredients)}")
    print(f"✅ 成功配對: {matched_count} ({matched_count/max(1, len(all_ingredients)):.2%})")
    print(f"💾 結果已儲存至: {output_filepath}")
    print("="*40)

if __name__ == "__main__":
    main()
