"""
版本更新紀錄：
V1 (20260422_113056): 初始版本，使用英文優化模型 all-MiniLM-L6-v2，中文語義捕捉能力較弱。
V2 (20260422_114535): 中文強化版，改用 paraphrase-multilingual-MiniLM-L12-v2 多國語言模型，提升對「牛奶/牛乳」語義關聯的理解。
V3 (20260422_115403): 混合加權版，改用中文特化模型 shibing624/text2vec-base-chinese，並加入「關鍵字加權邏輯 (Keyword Boost)」。
                若查詢詞精準出現在名稱或俗名中，將獲得額外相似度分數，解決語義分數過於接近的問題。
"""

import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'  # 隱藏 TensorFlow/PyTorch 警告資訊

import json
import numpy as np
from sentence_transformers import SentenceTransformer, util

# 1. 改用更精準的中文語意模型
print("正在載入中文強化 Embedding 模型 (text2vec-base-chinese)...")
model = SentenceTransformer('shibing624/text2vec-base-chinese')

def load_and_prepare_data(file_path):
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"找不到資料路徑: {file_path}")

    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    documents = []
    metadata_list = []
    
    for category, items in data.items():
        for item in items:
            name = item.get('樣品名稱', '')
            aliases = item.get('俗名', '')
            cat = item.get('食品分類', '')
            
            # 構建文本時，將「名稱」與「別名」作為權重核心
            doc_text = f"食品：{name}。別名：{aliases}。分類：{cat}"
            documents.append(doc_text)
            
            # 儲存 metadata 用於後續關鍵字加權比對
            metadata_list.append({
                "name": name,
                "aliases": aliases if aliases else "",
                "full_text": doc_text
            })
            
    return documents, metadata_list

# 檔案路徑使用你提供的 Windows 路徑
file_path = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json"
documents, metadata_list = load_and_prepare_data(file_path)

print(f"資料庫載入完成，共 {len(documents)} 筆資料。")
print("正在進行向量化索引 (Indexing)...")
doc_embeddings = model.encode(documents, convert_to_tensor=True)

def search_with_boost(query, k=5, boost_weight=0.08):
    """
    執行混合搜尋：語義相似度 + 關鍵字命中加權
    :param query: 使用者輸入的食材
    :param k: 顯示前幾個結果
    :param boost_weight: 關鍵字命中的加權分數 (預設為 0.08，可依測試結果微調)
    """
    # 取得語義相似度向量
    query_embedding = model.encode(query, convert_to_tensor=True)
    cos_scores = util.cos_sim(query_embedding, doc_embeddings)[0]
    
    final_results = []
    for i, score in enumerate(cos_scores):
        score_val = score.item()
        
        # --- 關鍵字加權 (Keyword Boost) ---
        # 如果查詢的詞直接包含在「樣品名稱」或「俗名」中，給予額外分數
        has_exact_match = (query in metadata_list[i]['name']) or (query in metadata_list[i]['aliases'])
        
        if has_exact_match:
            score_val += boost_weight
            
        final_results.append({
            "idx": i,
            "final_score": score_val,
            "is_boosted": has_exact_match
        })
    
    # 根據最終分數進行排序
    final_results.sort(key=lambda x: x['final_score'], reverse=True)
    
    print(f"\n{'='*80}")
    print(f"查詢食材: 【{query}】 (加權權重: {boost_weight})")
    print(f"{'排名':<4} | {'最終分數':<8} | {'加權':<4} | {'資料庫匹配文本'}")
    print("-" * 80)
    
    for i, res in enumerate(final_results[:k]):
        idx = res['idx']
        boost_mark = "★" if res['is_boosted'] else " "
        print(f"#{i+1:<3} | {res['final_score']:.4f} | {boost_mark:<4} | {documents[idx]}")
    print(f"{'='*80}\n")

if __name__ == "__main__":
    print("\n--- 營養資料庫 RAG 校對系統 V3 (混合加權版) ---")
    print("輸入 'exit' 結束程式。若精準命中名稱或俗名，排名旁會標註 ★。")
    
    while True:
        user_input = input("請輸入測試食材: ").strip()
        if user_input.lower() in ['exit', 'quit']: break
        if not user_input: continue
        search_with_boost(user_input)