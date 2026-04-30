"""
此版本實作分層檢索（Two-Stage Retrieval），能從根本上解決「特徵稀釋」的問題，
因為我們會在第二層的 Embedding 文本中完全拔除分類字眼，強迫模型只專注在食材名稱與俗名上。
"""

import json
import numpy as np
from sentence_transformers import SentenceTransformer, util
from tqdm import tqdm

print("正在載入中文強化 Embedding 模型 (shibing624/text2vec-base-chinese)...")
model = SentenceTransformer('shibing624/text2vec-base-chinese')

# 全域變數儲存分層索引
category_names = []           # 儲存所有分類名稱
category_embeddings = None    # 第一層：分類的向量
item_metadata_by_cat = {}     # 儲存每個分類下的 Metadata
item_embeddings_by_cat = {}   # 第二層：各分類下的食材向量


def build_two_stage_index(file_path):
    global category_names, category_embeddings, item_metadata_by_cat, item_embeddings_by_cat

    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    category_names = list(data.keys())

    # ==========================================
    # 第一層索引：為「食品分類」建立向量
    # ==========================================
    print("\n[1/2] 正在建立【第一層：分類大項】向量索引...")
    category_embeddings = model.encode(category_names, convert_to_tensor=True)

    # ==========================================
    # 第二層索引：為「分類內的食材」建立向量
    # ==========================================
    print("\n[2/2] 正在建立【第二層：細部食材】向量索引...")
    # 使用 tqdm 顯示各分類處理進度
    for cat in tqdm(category_names, desc="處理分類進度", unit="類"):
        items = data[cat]
        docs = []
        meta = []

        for item in items:
            name = item.get('樣品名稱', '')
            aliases = item.get('俗名', '')

            # 【關鍵改變】：這裡刻意「不放入」分類字眼，避免分數被稀釋
            # 讓模型純粹比對名稱與俗名
            doc_text = f"名稱：{name}。別名：{aliases}"

            docs.append(doc_text)
            meta.append({
                "name": name,
                "aliases": aliases,
                "full_text": doc_text
            })

        item_metadata_by_cat[cat] = meta
        if docs:
            item_embeddings_by_cat[cat] = model.encode(
                docs, convert_to_tensor=True)

    print("\n✅ 雙層索引建立完成！")


def search_two_stage(query, top_k_cats=1, top_k_items=5, boost_weight=0.05):
    query_emb = model.encode(query, convert_to_tensor=True)

    # --- 第一階段：尋找最匹配的分類 ---
    cat_scores = util.cos_sim(query_emb, category_embeddings)[0]
    top_cat_indices = np.argsort(-cat_scores.cpu())[:top_k_cats]

    print(f"\n{'='*75}")
    print(f"查詢食材: 【{query}】 (分層檢索模式)")
    print("-" * 75)

    all_candidates = []

    # --- 第二階段：在選中的分類中，尋找最匹配的食材 ---
    for cat_idx in top_cat_indices:
        target_cat = category_names[cat_idx]
        cat_score = cat_scores[cat_idx].item()
        print(f"🎯 [第一層命中] 鎖定分類：{target_cat} (分類相似度: {cat_score:.4f})")

        # 取出該分類下的所有食材向量與資料
        cat_item_embs = item_embeddings_by_cat.get(target_cat)
        cat_meta = item_metadata_by_cat.get(target_cat)

        if cat_item_embs is None:
            continue

        # 計算查詢詞與該分類下所有食材的相似度
        item_scores = util.cos_sim(query_emb, cat_item_embs)[0]

        for i, score in enumerate(item_scores):
            score_val = score.item()

            # 保留關鍵字加權機制 (Keyword Boost)
            if query in cat_meta[i]['name'] or query in cat_meta[i]['aliases']:
                score_val += boost_weight

            all_candidates.append(
                (score_val, target_cat, cat_meta[i]['full_text']))

    # 針對收集到的候選名單進行最終排序
    all_candidates.sort(key=lambda x: x[0], reverse=True)

    print(f"\n{'排名':<4} | {'最終分數':<8} | {'所屬分類':<12} | {'匹配文本'}")
    print("-" * 75)
    for i, (score, cat, text) in enumerate(all_candidates[:top_k_items]):
        # 為了排版整齊，限制分類字串顯示長度
        display_cat = cat[:6] + ".." if len(cat) > 6 else cat
        print(f"#{i+1:<3} | {score:.4f} | {display_cat:<10} | {text}")
    print(f"{'='*75}\n")


if __name__ == "__main__":
    # 指定你的資料庫檔案
    file_path = '2_nutrition_data_categorized_20260422_170816.json'

    try:
        build_two_stage_index(file_path)
    except FileNotFoundError:
        print(f"找不到檔案 {file_path}，請確認檔案路徑。")
        exit()

    print("輸入 'exit' 或 'quit' 可結束程式。")
    while True:
        user_input = input("請輸入測試食材: ").strip()
        if user_input.lower() in ['exit', 'quit']:
            break
        if not user_input:
            continue

        # 這裡設定 top_k_cats=2，代表第一層會抓取「最可能的前2個分類」交給第二層比對
        # 可以避免某些食材橫跨兩個分類的邊界
        search_two_stage(user_input, top_k_cats=2, top_k_items=5)
