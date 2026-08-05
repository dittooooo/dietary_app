"""
這兩個錯誤完美地暴露出我們上一個版本中「分層檢索（Two-Stage）」的致命傷！

為什麼會產生錯誤？
這兩個錯誤的根本原因都源自於 「第一層分類判斷的語意斷層」 以及 「容錯機制被假訊號攔截」：

語意與官方分類不符 (第一層找錯類別)：
無鹽奶油： 在人類的認知與 Embedding 模型的語意中，奶油高度關聯於「乳品類」。但你的營養資料庫將其歸類在「油脂類」。在第一層比對時，模型把前兩名分類給了「乳品類」和「加工食品類」，直接把「油脂類」淘汰了。
免煮麵皮： 語意上接近「加工食品」或「麵食」，但資料庫歸在「穀物類」。第一層比對時，模型根本沒有把「穀物類」排進前兩名。

容錯機制 (Fallback) 未啟動：
因為第一層找錯了分類，第二層只能在錯誤的分類裡找。
它在錯誤分類裡找到了「白醬」（裡面有奶油）和「乾麵條」，這些項目的相似度分數「剛好大於 0.65」，導致系統認為「我找到堪用的了」，因此 全域搜尋 (Fallback) 根本沒有被觸發。

怎麼修改？
對於幾千到幾萬筆的營養資料庫來說，現代的向量檢索速度極快，其實不需要做分層檢索 (Two-Stage)。 分層檢索通常是用在百萬級別以上的資料庫。我們過度優化，反而犧牲了精準度。

我們要做的修改有三點：
拔除分層機制，改為「全域扁平檢索 (Flat Global Search)」： 直接讓食材跟所有幾千筆資料庫同時比對，就不會有「走錯房間」的問題。
加入「內容物描述」進入向量： 你的預期結果中包含了 內容物描述，這個欄位充滿了關鍵語意（例如「杜蘭小麥粉」），必須加進去讓模型一起計算。
調高關鍵字加權權重： 將 boost_weight 從 0.05 提高到 0.15，確保只要「俗名」或「名稱」有精準命中，分數就能輾壓其他選項。
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
MODEL_NAME = "gpt-4.1-nano"

print("正在載入 Embedding 模型 (shibing624/text2vec-base-chinese)...")
embedder = SentenceTransformer('shibing624/text2vec-base-chinese')

# ==========================================
# 更新全域變數 (刪除分層用的變數，只留全域)
# ==========================================
global_metadata = []
global_embeddings = None
match_cache = {}

# ==========================================
# 修改 2. 建立檢索索引 (加入 null 值防呆處理)
# ==========================================


def build_indices(file_path):
    global global_metadata, global_embeddings

    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    global_docs = []
    global_metadata = []

    print("\n正在建立全域向量索引庫...")
    # 直接打平所有分類
    for cat, items in tqdm(data.items(), desc="處理資料進度"):
        for item in items:
            # 修正處：使用 or '' 確保當 JSON 值為 null (None) 時，強制轉為空字串
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
# 修改 3. 檢索邏輯 (扁平搜尋 + 高權重)
# ==========================================


def search_candidates(query, top_k=5, boost_weight=0.15):  # 提高加權至 0.15
    query_emb = embedder.encode(query, convert_to_tensor=True)

    # 直接與所有資料計算餘弦相似度
    scores = util.cos_sim(query_emb, global_embeddings)[0]

    all_candidates = []
    for i, score in enumerate(scores):
        score_val = score.item()

        # 強力關鍵字加權：字面上有命中，直接大幅加分
        if query in global_metadata[i]['name'] or query in global_metadata[i]['aliases']:
            score_val += boost_weight

        all_candidates.append((score_val, global_metadata[i]))

    # 排序並取前 K 名
    all_candidates.sort(key=lambda x: x[0], reverse=True)

    return all_candidates[:top_k], "Global Search"

# ==========================================
# 4. LLM 上下文重排序 (修正為 OpenAI 語法)
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
        # 修正處：改用 OpenAI Chat Completion 語法
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
# 5. 主處理管線
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
                resolved_ingredients.append(
                    {"original": target_name, "matched": match_cache[cache_key], "method": "Cache"})
                continue

            candidates, search_method = search_candidates(target_name)
            final_match = get_final_decision_from_llm(
                recipe_name=recipe_name,
                target_ingredient=target_name,
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
    RUN_MODE = "manual"

    # --- 控制範圍變數 (僅在 batch 模式有效) ---
    start_recipe_num = 0
    end_recipe_num = 2

    # 檔案路徑設定
    nutrition_file = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json"
    recipes_file = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\recipes_20260424_090733.json"

    # 無論哪種模式，都必須先建立向量資料庫索引
    build_indices(nutrition_file)

    if RUN_MODE == "manual":
        print("\n" + "="*60)
        print("🍳 進入手動查詢除錯模式 🍳")
        print("輸入 'exit' 或 'quit' 可結束程式。")
        print("="*60)

        while True:
            query = input("\n請輸入要查詢的食材: ").strip()
            if query.lower() in ['exit', 'quit']:
                break
            if not query:
                continue

            # 1. 執行向量檢索
            candidates, search_method = search_candidates(query)

            print(f"\n【RAG 向量檢索 Top-5】({search_method})")
            for i, (score, meta) in enumerate(candidates):
                print(
                    f"#{i+1:<2} | 分數: {score:.4f} | 分類: {meta['category']} | 名稱: {meta['name']} | 俗名: {meta['aliases']}")

            # 2. 模擬 LLM 決斷 (手動模式下無食譜上下文)
            print("\n🤖 正在交由 LLM 進行最終決斷...")
            final_match = get_final_decision_from_llm(
                recipe_name="無(手動測試)",
                target_ingredient=query,
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
