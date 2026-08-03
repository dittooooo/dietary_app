# recipes要先換成一人份的，且把適量都換成實際份量
"""
請根據data\recipes.json的"name"欄位
推測其"適量"應該是多少
"""

import json
import os
import math
from dotenv import load_dotenv
from openai import OpenAI

def get_embedding(text, client, model="text-embedding-3-small"):
    text = text.replace("\n", " ")
    return client.embeddings.create(input=[text], model=model).data[0].embedding

def cosine_similarity(v1, v2):
    dot_product = sum(a * b for a, b in zip(v1, v2))
    norm_v1 = math.sqrt(sum(a * a for a in v1))
    norm_v2 = math.sqrt(sum(b * b for b in v2))
    return dot_product / (norm_v1 * norm_v2) if norm_v1 * norm_v2 != 0 else 0

def match_ingredients(recipes_path="data/recipes.json", nutrition_path="data/nutrition_data.json", output_path="data/ingredient_mapping.json"):
    # 載入 .env 檔案中的環境變數
    load_dotenv()
    client = OpenAI(api_key=os.environ.get("GRAPHRAG_API_KEY"))

    print("讀取資料中...")
    with open(recipes_path, "r", encoding="utf-8") as f:
        recipes = json.load(f)
    with open(nutrition_path, "r", encoding="utf-8") as f:
        nutrition_data = json.load(f)

    # 1. 取得需要比對的食譜食材 (過濾出獨特名稱)
    unique_ingredients = set()
    for recipe in recipes:
        for ing in recipe.get("ingredients", []):
            name = ing.get("name", "").strip()
            if name:
                unique_ingredients.add(name)
    unique_ingredients = list(unique_ingredients)

    # 2. 建立營養資料庫字典
    nutrition_items = []
    for item in nutrition_data:
        name = item.get("樣品名稱", "").strip()
        # 若有俗名，可結合一起做 embedding 增加比對準確率
        alt_name = item.get("俗名")
        search_text = name if not alt_name else f"{name} {alt_name}"
        search_text = search_text.strip()
        if not search_text:
            continue
        nutrition_items.append({
            "id": item.get("整合編號", ""),
            "name": name,
            "search_text": search_text
        })
    
    print(f"共有 {len(unique_ingredients)} 種食譜食材，{len(nutrition_items)} 種營養成分資料。")
    
    # 3. 取得食譜食材的 Embedding
    print("正在取得食譜食材的 Embedding...")
    recipe_embeddings = {}
    batch_size = 1000
    for i in range(0, len(unique_ingredients), batch_size):
        batch = unique_ingredients[i:i+batch_size]
        response = client.embeddings.create(input=batch, model="text-embedding-3-small")
        for j, data in enumerate(response.data):
            recipe_embeddings[batch[j]] = data.embedding
        print(f"  已處理食譜食材 {i + len(batch)} / {len(unique_ingredients)} 筆...")
        
    # 4. 取得營養庫資料的 Embedding
    # 這裡將營養資料分批傳入 OpenAI API 取得 text-embedding 以加快速度
    print("正在取得營養庫的 Embedding... (這可能需要一些時間)")
    batch_size = 1000
    for i in range(0, len(nutrition_items), batch_size):
        batch = nutrition_items[i:i+batch_size]
        texts = [item["search_text"] for item in batch]
        # OpenAI 的 embeddings API 支援批次傳入
        response = client.embeddings.create(input=texts, model="text-embedding-3-small")
        for j, data in enumerate(response.data):
            batch[j]["embedding"] = data.embedding
        print(f"  已處理 {i + len(batch)} / {len(nutrition_items)} 筆...")

    # 5. 計算 Cosine Similarity 進行比對
    print("開始比對最接近的食材...")
    mapping_result = {}
    for ing, r_emb in recipe_embeddings.items():
        best_match = None
        best_score = -1
        
        for item in nutrition_items:
            score = cosine_similarity(r_emb, item["embedding"])
            if score > best_score:
                best_score = score
                best_match = item
                
        mapping_result[ing] = {
            "matched_id": best_match["id"],
            "matched_name": best_match["name"],
            "similarity_score": round(best_score, 4)
        }
        print(f"[{ing}] 對應到 -> [{best_match['name']}] (相似度: {score:.4f})")

    # 6. 儲存結果
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(mapping_result, f, ensure_ascii=False, indent=4)
        
    print(f"\n✅ 比對完成！結果已存至 {output_path}")

if __name__ == "__main__":
    match_ingredients()
