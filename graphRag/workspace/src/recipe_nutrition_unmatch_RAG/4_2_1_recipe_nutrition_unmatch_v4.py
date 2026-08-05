"""
rag_two_stage.py

B. 分層檢索 (Two-Stage Retrieval)
如果資料量很大，可以改變搜尋策略：
第一層： 先讓 LLM 或簡單的比對器決定「這屬於哪個分類？」（例如：這屬於乳品類）。
第二層： 只在「乳品類」的子集合中進行向量搜尋。
效果： 徹底消除不同分類間的干擾，也能提高搜尋速度。

rag_two_stage.py有一個非常重要的前提
那就是分類必須分的很正確完整
像是"貢丸"得先被辨識出是加工食品
才能精準對應到"加工食品"的"冷凍貢丸"
如果分類錯誤，被分到"肉品"
那就會沒有機會挽回了
幫我想一個fallback來解決這類問題

"""

"""
Genimi回答 : 
這兩個問題都非常切中真實世界 RAG 系統的痛點！

第一個是**「硬邊界（Hard Boundary）問題」**：一旦第一層分類判斷錯誤，第二層就永遠找不到正確答案。
第二個是**「上下文孤島（Context Isolation）問題」**：單看「紅酒」，系統不知道它是要燉肉還是煮甜湯。



針對這兩個問題，我們可以透過**「全域容錯機制（Global Fallback）」**與**「LLM 上下文重排序（LLM Contextual Reranking）」**來完美解決。以下是具體的機制設計與實作邏輯：

### 解決方案一：全域容錯機制 (Global Fallback)

為了避免「貢丸」被錯誤分類而導致找不到，我們可以設定一個**「信心分數閾值（Threshold）」**。

1.  **正常雙層檢索：** 先讓系統走正常的分層檢索。
2.  **啟動 Fallback：** 如果雙層檢索找出的 Top-1 食材，其相似度分數**低於某個標準（例如 0.65）**，系統就會意識到：「我可能找錯分類了！」
3.  **全域扁平搜尋：** 此時系統自動切換到「第一代」的做法，直接把「貢丸」拿去跟資料庫裡**所有**的食材進行比對（忽略分類），把真正的「冷凍貢丸」救回來。

### 解決方案二：結合食譜上下文的 LLM 判斷 (Context-Aware Reranking)

這是一個極佳的防呆機制！RAG 負責找出「字面上或語意上」最像的前 5 名候選人，而 LLM 負責擔任「主廚」，結合 N-1 個食材來做最終的邏輯推理。

在你的 `recipe_nutrition_unmatch` 流程中，這個機制會實作在 **Prompt 設計階段**。

#### 實作邏輯與 Prompt 範本設計

當你要處理「義式千層麵」裡的第 N 個食材（假設是紅酒，但 RAG 抓出了紅豆跟紅葡萄酒）時，你可以將組態寫在 `.env` 中的 LLM 拿來發送以下結構的 Prompt：

```text
你是一個專業的營養學資料對應專家。請根據食譜的上下文，從【候選清單】中挑選出最合理對應【目標食材】的營養庫項目。

【食譜資訊】
食譜名稱：義式千層麵
其他共演食材：免煮麵皮, 披薩起士絲, 洋蔥, 豬絞肉, 蕃茄糊, 蒜蓉...

【目標食材】
原始名稱：紅酒

【候選清單】(由向量資料庫檢索提供)
1. 分類：豆類。名稱：紅豆。別名：赤小豆
2. 分類：飲料類。名稱：紅葡萄酒。別名：紅酒
3. 分類：飲料類。名稱：白葡萄酒。別名：白酒
4. ...

【任務規則】
1. 請推理「目標食材」在此食譜中扮演的角色。
2. 考量西方料理（如義式千層麵）通常使用何種食材搭配豬絞肉與蕃茄糊。
3. 只能從【候選清單】中輸出最合理的一項的完整名稱，不需解釋原因。
```

透過這種方式，LLM 擁有強大的世界知識（World Knowledge），它一看就知道：**「千層麵的肉醬需要紅葡萄酒來燉煮，絕對不可能加紅豆。」** 這樣就能精準過濾掉向量檢索造成的荒謬錯誤。

### 程式碼整合藍圖

如果將這兩個機制整合進你目前的 Python 系統中，程式碼的結構會像這樣：

```python
# 假設這是你處理單一食譜的迴圈
def process_recipe_ingredients(recipe_name, ingredients_list):
    resolved_ingredients = []
    
    # 針對這個食譜建立一個上下文清單 (N-1)
    all_names = [ing['name'] for ing in ingredients_list]
    
    for i, target_ing in enumerate(ingredients_list):
        query = target_ing['name']
        context_others = [name for j, name in enumerate(all_names) if j != i]
        
        # 1. 雙層檢索 (Two-Stage RAG)
        best_score, top_candidates = search_two_stage(query)
        
        # 2. 全域容錯機制 (Global Fallback)
        if best_score < 0.65: # 信心不足，啟動挽救機制
            print(f"⚠️ [{query}] 分數過低 ({best_score})，啟動全域檢索...")
            top_candidates = search_global_all_items(query) # 直接搜尋全部資料
            
        # 3. LLM 上下文重排序 (Context-Aware Reranking)
        # 將 top_candidates 轉換為字串清單
        candidates_text = format_candidates_for_prompt(top_candidates)
        
        # 呼叫 LLM API，傳入食譜名稱、剩餘食材、以及候選名單
        final_match = call_llm_for_final_decision(
            recipe_name=recipe_name,
            target=query,
            context=context_others,
            candidates=candidates_text
        )
        
        resolved_ingredients.append({
            "original": query,
            "matched_nutrition": final_match
        })
        
    return resolved_ingredients
```

### 為什麼這樣設計最完美？
1. **效能與成本平衡：** 第一與第二步的向量檢索（RAG）都在本地端執行，速度極快且無 API 成本。只有在最後「給出名單做選擇」時才呼叫 LLM。
2. **解決無解題：** 如果單看「紅酒」，有些 RAG 模型真的會因為字數較少或訓練語料庫的問題給出奇怪的排名。加入了 `recipe_name` 與 `context_others`，就像給了 LLM 一雙眼睛，徹底消滅了「把紅酒當紅豆」的笑話。
3. **高可維護性：** 你不用寫一堆死板的 `if-else` 規則（例如 if 食譜=千層麵 then 排除紅豆），將複雜的常識判斷全權交給 LLM，讓你的系統具備高度的擴展性。

"""

"""
這是一份為你整合了「雙層檢索」、「全域容錯（Fallback）」、「LLM 上下文重排序」以及「快取機制（Caching）」的完整系統程式碼。
為了確保長期維護性與執行效率，這支程式碼（我們暫且稱之為 recipe_nutrition_unmatch_v4.py）
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

category_names = []
category_embeddings = None
item_metadata_by_cat = {}
item_embeddings_by_cat = {}

global_metadata = []
global_embeddings = None

match_cache = {}

# ==========================================
# 2. 建立檢索索引
# ==========================================


def build_indices(file_path):
    global category_names, category_embeddings
    global item_metadata_by_cat, item_embeddings_by_cat
    global global_metadata, global_embeddings

    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    category_names = list(data.keys())
    category_embeddings = embedder.encode(
        category_names, convert_to_tensor=True)

    global_docs = []

    print("\n正在建立向量索引庫...")
    for cat in tqdm(category_names, desc="處理分類進度", unit="類"):
        items = data[cat]
        docs_for_cat = []
        meta_for_cat = []

        for item in items:
            name = item.get('樣品名稱', '') or ""
            # 確保 aliases 永遠是字串，避免 NoneType 錯誤
            aliases = item.get('俗名', '') or ""

            doc_text = f"名稱：{name}。別名：{aliases}"
            global_text = f"分類：{cat}。名稱：{name}。別名：{aliases}"
            meta_data = {"name": name, "aliases": aliases,
                         "category": cat, "full_text": global_text}

            docs_for_cat.append(doc_text)
            meta_for_cat.append(meta_data)
            global_docs.append(global_text)
            global_metadata.append(meta_data)

        item_metadata_by_cat[cat] = meta_for_cat
        if docs_for_cat:
            item_embeddings_by_cat[cat] = embedder.encode(
                docs_for_cat, convert_to_tensor=True)

    global_embeddings = embedder.encode(global_docs, convert_to_tensor=True)
    print("✅ 雙層與全域索引建立完成！\n")

# ==========================================
# 3. 檢索邏輯
# ==========================================


def search_candidates(query, fallback_threshold=0.65, top_k=5, boost_weight=0.05):
    query_emb = embedder.encode(query, convert_to_tensor=True)
    cat_scores = util.cos_sim(query_emb, category_embeddings)[0]
    top_cat_indices = np.argsort(-cat_scores.cpu())[:2]

    all_candidates = []
    for cat_idx in top_cat_indices:
        target_cat = category_names[cat_idx]
        cat_item_embs = item_embeddings_by_cat.get(target_cat)
        cat_meta = item_metadata_by_cat.get(target_cat)
        if cat_item_embs is None:
            continue

        item_scores = util.cos_sim(query_emb, cat_item_embs)[0]
        for i, score in enumerate(item_scores):
            score_val = score.item()
            # 修正處：確保 aliases 不為 None
            name_val = cat_meta[i]['name'] or ""
            alias_val = cat_meta[i]['aliases'] or ""
            if query in name_val or query in alias_val:
                score_val += boost_weight
            all_candidates.append((score_val, cat_meta[i]))

    all_candidates.sort(key=lambda x: x[0], reverse=True)
    best_score = all_candidates[0][0] if all_candidates else 0

    if best_score < fallback_threshold:
        global_scores = util.cos_sim(query_emb, global_embeddings)[0]
        global_candidates = []
        for i, score in enumerate(global_scores):
            score_val = score.item()
            name_val = global_metadata[i]['name'] or ""
            alias_val = global_metadata[i]['aliases'] or ""
            if query in name_val or query in alias_val:
                score_val += boost_weight
            global_candidates.append((score_val, global_metadata[i]))
        global_candidates.sort(key=lambda x: x[0], reverse=True)
        return global_candidates[:top_k], "Global Fallback"

    return all_candidates[:top_k], "Two-Stage"

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
    start_recipe_num = 0
    end_recipe_num = 2

    # 使用原始路徑
    nutrition_file = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json"
    recipes_file = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\recipes.json"

    import datetime
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = f"C:/Users/PARALELL/Desktop/code4/workspace/src/recipe_nutrition_unmatch_RAG/data/output/{timestamp}"
    os.makedirs(output_dir, exist_ok=True)
    output_file = os.path.join(output_dir, 'resolved_recipes_output.json')

    build_indices(nutrition_file)
    print(f"開始處理食譜比對作業 (範圍: {start_recipe_num} 到 {end_recipe_num})...")

    final_results = process_recipes(
        recipes_file, start_idx=start_recipe_num, end_idx=end_recipe_num)

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(final_results, f, ensure_ascii=False, indent=2)

    print(f"\n✅ 處理完成！結果已儲存至 {output_file}")
