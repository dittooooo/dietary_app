"""
這個版本（recipe_nutrition_unmatch_v5.py）包含了我們剛才討論過的所有優化：

全域扁平檢索 (Flat Global Search)：避免分層錯誤，並加入了 內容物描述 以提升語意。

Null 值防呆處理：讀取 JSON 時使用 or ''，避免遇到缺失值引發 TypeError。

同義詞字典 (Synonym Normalization)：在比對前統一「起士」與「起司」等異體字。

雙向關鍵字加權 (Bi-directional Keyword Boost)：解決「披薩起司絲」與「起司絲」包容關係的計分問題。

LLM 查詢前轉換 (Query Transformation)：利用 LLM 自動拔除品牌與多餘修飾詞，並設有專屬快取 (normalize_cache)。

雙模式切換 (RUN_MODE)：可以自由切換 manual 手動除錯，或 batch 批次寫入檔案。

請將以下程式碼儲存並執行。你可以先在 RUN_MODE = "manual" 下輸入「披薩起士絲」或「三元豬小腸」來體驗完整的淨化與比對流程！
"""

import json
import os
import numpy as np
from sentence_transformers import SentenceTransformer, util
from tqdm import tqdm
from dotenv import load_dotenv
from openai import OpenAI

# ==========================================
# 1. 初始化與組態設定
# ==========================================
load_dotenv()
API_KEY = os.getenv("OPENAI_API_KEY")
if not API_KEY:
    raise ValueError("請在 .env 檔案中設定 OPENAI_API_KEY")

# 初始化 OpenAI 客戶端
client = OpenAI(api_key=API_KEY)
MODEL_NAME = "gpt-4.1-nano"  # 請依據你的環境替換為實際使用的模型 (例如 gpt-4o, gpt-3.5-turbo 等)

print("正在載入 Embedding 模型 (shibing624/text2vec-base-chinese)...")
embedder = SentenceTransformer('shibing624/text2vec-base-chinese')

# ==========================================
# 全域變數與快取機制
# ==========================================
global_metadata = []
global_embeddings = None
match_cache = {}       # 快取: (食譜名_原始食材名) -> 最終對應結果
normalize_cache = {}   # 快取: 原始食材名 -> 淨化後的核心食材名

# ==========================================
# 2. 建立檢索索引 (全域扁平檢索 + Null 防呆)
# ==========================================


def build_indices(file_path):
    global global_metadata, global_embeddings

    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    global_docs = []
    global_metadata = []

    print("\n正在建立全域向量索引庫...")
    for cat, items in tqdm(data.items(), desc="處理資料進度"):
        for item in items:
            # 使用 or '' 確保當 JSON 值為 null (None) 時，強制轉為空字串
            name = item.get('樣品名稱') or ''
            aliases = item.get('俗名') or ''
            desc = item.get('內容物描述') or ''

            # 建構富含所有資訊的文本
            global_text = f"分類：{cat}。名稱：{name}。別名：{aliases}。描述：{desc}"

            meta_data = {
                "name": name,
                "aliases": aliases,
                "category": cat,
                "full_text": global_text
            }

            global_docs.append(global_text)
            global_metadata.append(meta_data)

    # 一次性將所有資料向量化
    global_embeddings = embedder.encode(global_docs, convert_to_tensor=True)
    print(f"✅ 全域索引建立完成！共 {len(global_docs)} 筆資料。\n")

# ==========================================
# 3. 查詢前處理 (LLM 淨化 + 字典正規化)
# ==========================================


def get_core_ingredient(raw_ingredient):
    """利用 LLM 拔除品牌、狀態等修飾詞，取得核心食材"""
    if raw_ingredient in normalize_cache:
        return normalize_cache[raw_ingredient]

    prompt = f"""
你是一個食材名稱標準化專家。請提取以下食譜食材的「核心食材名稱」。
規則：
1. 去除品牌名稱（如：三元豬小腸 -> 豬小腸）
2. 去除多餘的用途與料理狀態修飾詞（如：免煮麵皮 -> 麵皮、熟白芝麻 -> 白芝麻）
3. 嚴格規定：不要做任何解釋，直接輸出淨化後的核心名詞即可。

原始食材：{raw_ingredient}
核心食材："""
    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[{"role": "user", "content": prompt}],
            temperature=0
        )
        clean_name = response.choices[0].message.content.strip()
        normalize_cache[raw_ingredient] = clean_name
        return clean_name
    except Exception as e:
        print(f"淨化詞彙時發生錯誤: {e}")
        return raw_ingredient

# 需保留，未來可繼續擴充


def normalize_ingredient(query):
    """硬規則：統一同音異字"""
    synonyms = {
        "起士": "起司",
        "芝士": "起司",
        "乳酪": "起司",
        "蕃茄": "番茄",
        "馬鈴薯": "洋芋"
    }
    normalized = query
    for old, new in synonyms.items():
        normalized = normalized.replace(old, new)
    return normalized

# ==========================================
# 4. 檢索邏輯 (正規化 + 雙向關鍵字加權)
# ==========================================


def search_candidates(raw_query, top_k=5, boost_weight=0.15):
    # 1. 查詢詞字串正規化
    query = normalize_ingredient(raw_query)
    query_emb = embedder.encode(query, convert_to_tensor=True)

    scores = util.cos_sim(query_emb, global_embeddings)[0]
    all_candidates = []

    for i, score in enumerate(scores):
        score_val = score.item()
        db_name = global_metadata[i]['name']
        db_aliases = global_metadata[i]['aliases'].split(',')

        # 2. 雙向關鍵字加權
        if query in db_name or query in global_metadata[i]['aliases']:
            score_val += boost_weight
        else:
            for alias in db_aliases:
                alias = alias.strip()
                if len(alias) > 1 and alias in query:
                    score_val += boost_weight
                    break

        all_candidates.append((score_val, global_metadata[i]))

    all_candidates.sort(key=lambda x: x[0], reverse=True)
    return all_candidates[:top_k], "Global Search"

# ==========================================
# 5. LLM 上下文重排序
# ==========================================


def get_final_decision_from_llm(recipe_name, target_ingredient, other_ingredients, candidates):
    candidates_text = ""
    for i, (_, meta) in enumerate(candidates):
        candidates_text += f"{i+1}. 分類：{meta['category']}。名稱：{meta['name']}。俗名：{meta['aliases']}\n"

    prompt = f"""
你是一個專業的營養學資料對應專家。請根據食譜的上下文，從【候選清單】中挑選出最合理對應【目標食材】的營養庫項目。

【食譜資訊】
食譜名稱：{recipe_name}
其他共演食材：{', '.join(other_ingredients)}

【目標食材】
原始名稱：{target_ingredient}

【候選清單】
{candidates_text}

【任務規則】
1. 觀察食譜名稱與其他食材，推理「目標食材」在此食譜中扮演的角色。
2. 只能從【候選清單】中挑選出最合理的一項。
3. 嚴格遵守直接還原規則：不要做任何解釋，不要增加標點符號，直接輸出你選中的「名稱」即可（例如：高脂鮮乳）。
4. 如果候選清單完全不合理，請輸出「無對應」。
"""
    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": "你是一位營養學與食譜對應專家。"},
                {"role": "user", "content": prompt}
            ],
            temperature=0
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        print(f"\nLLM 發生錯誤: {e}")
        return candidates[0][1]['name']

# ==========================================
# 6. 主處理管線
# ==========================================


def process_recipes(recipes_file_path, start_idx=0, end_idx=None):
    with open(recipes_file_path, 'r', encoding='utf-8') as f:
        recipes = json.load(f)

    target_recipes = recipes[start_idx:end_idx]
    results = []

    for recipe in tqdm(target_recipes, desc="分析食譜進度", unit="道"):
        recipe_name = recipe.get("name", "未命名食譜")
        ingredients = recipe.get("ingredients", [])
        all_ing_names = [ing.get("name")
                         for ing in ingredients if ing.get("name")]

        resolved_ingredients = []
        for i, target_name in enumerate(all_ing_names):
            context_others = [name for j,
                              name in enumerate(all_ing_names) if j != i]
            cache_key = f"{recipe_name}_{target_name}"

            if cache_key in match_cache:
                resolved_ingredients.append({
                    "original": target_name,
                    "matched": match_cache[cache_key],
                    "method": "Cache"
                })
                continue

            # 🌟 步驟 0：查詢前轉換 (LLM 淨化)
            clean_target_name = get_core_ingredient(target_name)

            # 🌟 步驟 1：檢索候選清單
            candidates, search_method = search_candidates(clean_target_name)

            # 🌟 步驟 2：結合上下文交給 LLM 決斷
            final_match = get_final_decision_from_llm(
                recipe_name=recipe_name,
                target_ingredient=target_name,  # 給 LLM 看原始名字，幫助理解上下文
                other_ingredients=context_others,
                candidates=candidates
            )

            match_cache[cache_key] = final_match
            resolved_ingredients.append({
                "original": target_name,
                "matched": final_match,
                "method": f"{search_method} + LLM"
            })

        results.append({
            "recipe_id": recipe.get("recipe_id"),
            "recipe_name": recipe_name,
            "resolved_ingredients": resolved_ingredients
        })

    return results


if __name__ == "__main__":
    # ==========================================
    # 模式切換開關
    # "batch"  : 讀取 recipes.json 進行批次處理並輸出檔案
    # "manual" : 在 cmd 手動輸入單一食材，即時查看檢索與 LLM 判斷結果
    # ==========================================
    RUN_MODE = "batch"

    # --- 控制範圍變數 (僅在 batch 模式有效) ---
    start_recipe_num = 5
    end_recipe_num = 10

    # 使用你的原始路徑
    nutrition_file = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json"
    recipes_file = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\recipes_20260424_090733.json"

    build_indices(nutrition_file)

    if RUN_MODE == "manual":
        print("\n" + "="*60)
        print("🍳 進入手動查詢除錯模式 🍳")
        print("輸入 'exit' 或 'quit' 可結束程式。")
        print("="*60)

        while True:
            raw_query = input("\n請輸入要查詢的食材: ").strip()
            if raw_query.lower() in ['exit', 'quit']:
                break
            if not raw_query:
                continue

            # 🌟 步驟 0：LLM 淨化查詢詞
            clean_query = get_core_ingredient(raw_query)
            print(f"✨ LLM 淨化查詢詞: 【 {raw_query} 】 -> 【 {clean_query} 】")

            # 🌟 步驟 1：執行向量檢索
            candidates, search_method = search_candidates(clean_query)

            print(f"\n【RAG 向量檢索 Top-5】({search_method})")
            for i, (score, meta) in enumerate(candidates):
                print(
                    f"#{i+1:<2} | 分數: {score:.4f} | 分類: {meta['category']} | 名稱: {meta['name']} | 俗名: {meta['aliases']}")

            # 🌟 步驟 2：模擬 LLM 決斷
            print("\n🤖 正在交由 LLM 進行最終決斷...")
            final_match = get_final_decision_from_llm(
                recipe_name="無(手動測試)",
                target_ingredient=raw_query,
                other_ingredients=["無(手動測試無其他共演食材)"],
                candidates=candidates
            )

            print(f"👉 LLM 最終對應結果: 【 {final_match} 】\n")
            print("-" * 60)

    elif RUN_MODE == "batch":
        import datetime
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        output_dir = f"C:/Users/PARALELL/Desktop/code4/workspace/src/recipe_nutrition_unmatch_RAG/data/output/{timestamp}"
        os.makedirs(output_dir, exist_ok=True)
        output_file = os.path.join(output_dir, 'resolved_recipes_output.json')

        print(f"開始處理食譜比對作業 (範圍: {start_recipe_num} 到 {end_recipe_num})...")

        final_results = process_recipes(
            recipes_file, start_idx=start_recipe_num, end_idx=end_recipe_num)

        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(final_results, f, ensure_ascii=False, indent=2)

        print(f"\n✅ 批次處理完成！結果已儲存至 {output_file}")

    else:
        print("錯誤的 RUN_MODE 設定！請設定為 'manual' 或 'batch'")
