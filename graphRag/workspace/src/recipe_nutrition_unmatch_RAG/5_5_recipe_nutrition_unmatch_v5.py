"""
5_2_recipe_nutrition_unmatch_v5.py

的錯誤匹配如下



"recipe_name": "麻藥蝦",

      {

        "original": "醬油",

        "matched": "壽司醋",

        "method": "Global Search + LLM"

      },

---

"recipe_name": "雞腿排",

      {

        "original":"醬油",

        "matched":"魚露",

        "method":"Global Search + LLM"

      },


應匹配為醬油 
"""

"""
這真是一個非常精彩的 Edge Case（邊角案例）！
你發現了目前檢索系統中一個隱藏的「加權碰撞（Feature Collision）」問題。

為什麼「醬油」會變成「壽司醋」？
在我們的營養資料庫中，「壽司醋」的俗名裡面包含了 "壽司醬油"，而「糖醋醬」的俗名包含了 "糖醋醬油"。
當你的 clean_target_name 是 "醬油" 時，系統去檢查：

"醬油" 有沒有包含在 "黃豆醬油" (一般醬油) 裡？有！加 0.15 分。
"醬油" 有沒有包含在 "壽司醬油" (壽司醋) 裡？有！加 0.15 分。
結果就是，資料庫裡高達三十幾種名稱含有「醬油」的調味料，全部都獲得了 +0.15 的加分！ 
在大家都加分的情況下，真正的「醬油」並沒有獲得優勢，
甚至可能因為 Embedding 向量模型某些微小的波動，被「壽司醋」擠出了 Top-10 的榜單。
當 LLM 看不到標準的醬油時，它就會被迫從「壽司醋」、「魚露」中瞎猜一個。

如何解決？ (導入「分級加權機制」)
我們必須教導檢索系統區分 「完全相等 (Exact Match)」 與 「部分包含 (Substring Match)」 的差異。
如果使用者的食材與資料庫的名稱或某個俗名「一模一樣」，我們應該給予一個輾壓級的超高權重（例如 +0.5），
保證它絕對排在第一名！
"""

from dotenv import load_dotenv
from openai import OpenAI
from tqdm import tqdm
from sentence_transformers import SentenceTransformer, util
import numpy as np
import os
import json

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

# 新增功能：快取持久化 - 設定快取檔案的儲存路徑與資料夾
CACHE_DIR = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\output\cache_data"
os.makedirs(CACHE_DIR, exist_ok=True)
NORMALIZE_CACHE_FILE = os.path.join(CACHE_DIR, 'normalize_cache.json')
MATCH_CACHE_FILE = os.path.join(CACHE_DIR, 'match_cache.json')

# 新增功能：快取持久化 - 建立讀取快取檔案的函式


def load_cache(filepath):
    if os.path.exists(filepath):
        with open(filepath, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {}  # 如果檔案不存在，則回傳空字典

# 新增功能：快取持久化 - 建立儲存快取檔案的函式


def save_all_caches():
    with open(NORMALIZE_CACHE_FILE, 'w', encoding='utf-8') as f:
        json.dump(normalize_cache, f, ensure_ascii=False, indent=2)
    with open(MATCH_CACHE_FILE, 'w', encoding='utf-8') as f:
        json.dump(match_cache, f, ensure_ascii=False, indent=2)
    print(f"\n💾 快取進度已成功持久化儲存至 {CACHE_DIR}/")


# 新增功能：快取持久化 - 程式啟動時，自動載入先前的快取紀錄
match_cache = load_cache(MATCH_CACHE_FILE)
normalize_cache = load_cache(NORMALIZE_CACHE_FILE)

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
            name = item.get('樣品名稱') or ''
            aliases = item.get('俗名') or ''
            desc = item.get('內容物描述') or ''

            # 🌟 新增：讀取整合編號
            item_id = item.get('整合編號') or 'Unknown'

            global_text = f"分類：{cat}。名稱：{name}。別名：{aliases}。描述：{desc}"

            meta_data = {
                "name": name,
                "aliases": aliases,
                "category": cat,
                "full_text": global_text,
                "id": item_id  # 🌟 新增：將編號存入 metadata
            }

            global_docs.append(global_text)
            global_metadata.append(meta_data)

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
3. 拔除產地或特定風味名稱，還原為最基礎的食材泛稱（例如：關廟麵 -> 乾麵條、讚岐烏龍麵 -> 烏龍麵、東港櫻花蝦 -> 櫻花蝦）。
4. 嚴格規定：不要做任何解釋，直接輸出淨化後的核心名詞即可。

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
        "馬鈴薯": "洋芋",
        "關廟麵": "乾麵條",
        "鮮奶": "高脂鮮乳",   # 🌟 新增：直接對應到明確的資料庫標準名
        "牛奶": "高脂鮮乳",   # 🌟 確保所有牛奶稱呼口徑一致

    }
    normalized = query
    for old, new in synonyms.items():
        normalized = normalized.replace(old, new)
    return normalized

# ==========================================
# 修改 4. 檢索邏輯 (導入分級關鍵字加權)
# ==========================================


def search_candidates(raw_query, top_k=10, boost_weight=0.15):
    # 1. 查詢詞字串正規化
    query = normalize_ingredient(raw_query)
    query_emb = embedder.encode(query, convert_to_tensor=True)

    scores = util.cos_sim(query_emb, global_embeddings)[0]
    all_candidates = []

    for i, score in enumerate(scores):
        score_val = score.item()
        db_name = global_metadata[i]['name']

        # 將別名切分為陣列，並去除前後空白
        db_aliases = [a.strip() for a in global_metadata[i]
                      ['aliases'].split(',') if a.strip()]

        # --------------------------------------------------
        # 2. 雙向關鍵字加權 (分級機制)
        # --------------------------------------------------
        # 【級別 A：絕對精準命中】 (完全等於名稱，或完全等於某個別名)
        # 給予 +0.5 的輾壓級權重，確保如「醬油」對「醬油」必定排在第一
        if query == db_name or query in db_aliases:
            score_val += 0.5

        # 【級別 B：部分包含命中】 (包含在名稱中，或雙向包含)
        # 給予 +0.15 的一般權重，處理如「披薩起司絲」與「起司絲」的關係
        elif query in db_name or query in global_metadata[i]['aliases']:
            score_val += boost_weight
        else:
            for alias in db_aliases:
                if len(alias) > 1 and alias in query:
                    score_val += boost_weight
                    break

        all_candidates.append((score_val, global_metadata[i]))

    # 排序並取前 K 名
    all_candidates.sort(key=lambda x: x[0], reverse=True)
    return all_candidates[:top_k], "Global Search"


# ==========================================
# 修改 5. LLM 上下文重排序
# ==========================================
def get_final_decision_from_llm(recipe_name, target_ingredient, other_ingredients, candidates):
    candidates_text = ""
    for i, (_, meta) in enumerate(candidates):
        # 這裡從 metadata 中安全讀取整合編號（若無則顯示 Unknown）
        item_id = meta.get('整合編號', meta.get('id', 'Unknown'))
        candidates_text += f"{i+1}. 分類：{meta['category']}。名稱：{meta['name']}。編號：{item_id}。俗名：{meta['aliases']}\n"

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
1. 絕對優先 (直白還原)：如果【候選清單】中有項目的「名稱」或「俗名」與【目標食材】字面完全相同或高度涵蓋（例如：醬油對應「一般醬油」），請直接選擇它！絕對不要以廚師的角度過度替換食材。
2. 上下文防呆：只有當字面無法直接對應，或出現歧義時（例如目標食材是紅酒，清單有紅豆與紅葡萄酒），才觀察食譜上下文來排除荒謬的選項。
3. 嚴格遵守直接還原規則：不要做任何解釋，不要增加標點符號。
4. 如果候選清單完全不合理，請輸出「名稱: 無對應 | 編號: None」。
5. 如果有選中項目，請嚴格按照以下格式填空回傳（請填入正確的真實名稱與編號，且不要加括號）：
例如 -> 名稱: 傳統醬油 | 編號: C0100101
"""
    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": "你是一位嚴謹的營養學與食譜對應專家，以字面精準對應為第一優先。"},
                {"role": "user", "content": prompt}
            ],
            temperature=0
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        print(f"\nLLM 發生錯誤: {e}")
        item_id = candidates[0][1].get(
            '整合編號', candidates[0][1].get('id', 'Unknown'))
        return f"名稱: {candidates[0][1]['name']} | 編號: {item_id}"


# ==========================================
# 6. 主處理管線
# ==========================================
def process_recipes(recipes_file_path, start_idx=0, end_idx=None, log_file_path=None):
    # 建立一個輔助寫入函數
    def log_to_file(text):
        if log_file_path:
            with open(log_file_path, 'a', encoding='utf-8') as lf:
                lf.write(text + '\n')

    with open(recipes_file_path, 'r', encoding='utf-8') as f:
        recipes = json.load(f)

    target_recipes = recipes[start_idx:end_idx]
    results = []

    for recipe in tqdm(target_recipes, desc="分析食譜進度", unit="道"):
        recipe_name = recipe.get("name", "未命名食譜")
        ingredients = recipe.get("ingredients", [])
        all_ing_names = [ing.get("name")
                         for ing in ingredients if ing.get("name")]

        # 在 TXT 中標示現在跑到哪道食譜
        log_to_file("\n" + "="*60)
        log_to_file(f"📝 食譜: 【 {recipe_name} 】")
        log_to_file("="*60)

        resolved_ingredients = []
        for i, target_name in enumerate(all_ing_names):
            context_others = [name for j,
                              name in enumerate(all_ing_names) if j != i]
            cache_key = f"{recipe_name}_{target_name}"

            log_to_file(f"\n請輸入要查詢的食材: {target_name}")

            if cache_key in match_cache:
                cached_data = match_cache[cache_key]
                if isinstance(cached_data, dict):
                    matched_name = cached_data.get("name", "")
                    matched_id = cached_data.get("整合編號", "")
                else:
                    matched_name = cached_data
                    matched_id = "Unknown"

                log_to_file(
                    f"👉 (Cache 命中) 最終對應結果: 【 名稱: {matched_name} | 整合編號: {matched_id} 】\n")
                log_to_file("-" * 60)

                resolved_ingredients.append({
                    "original": target_name,
                    "matched": matched_name,
                    "整合編號": matched_id,
                    "method": "Cache"
                })
                continue

            # 🌟 步驟 0：查詢前轉換 (LLM 淨化)
            clean_target_name = get_core_ingredient(target_name)
            log_to_file(
                f"✨ LLM 淨化查詢詞: 【 {target_name} 】 -> 【 {clean_target_name} 】")

            # 🌟 步驟 1：檢索候選清單
            candidates, search_method = search_candidates(
                clean_target_name, top_k=10)

            log_to_file(f"\n【RAG 向量檢索 Top-10】({search_method})")
            for j, (score, meta) in enumerate(candidates):
                item_id = meta.get('整合編號', meta.get('id', 'Unknown'))
                log_to_file(
                    f"#{j+1:<2} | 分數: {score:.4f} | 分類: {meta['category']} | 編號: {item_id} | 名稱: {meta['name']} | 俗名: {meta['aliases']}")

            # 🌟 步驟 2：結合上下文交給 LLM 決斷
            log_to_file("\n🤖 正在交由 LLM 進行最終決斷...")
            full_match_str = get_final_decision_from_llm(
                recipe_name=recipe_name,
                target_ingredient=target_name,
                other_ingredients=context_others,
                candidates=candidates
            )

            # 解析 LLM 的回傳字串
            try:
                if "|" in full_match_str:
                    parts = full_match_str.split('|')
                    matched_name = parts[0].split(
                        ':')[1].strip().replace('[', '').replace(']', '')
                    matched_id = parts[1].split(':')[1].strip().replace(
                        '[', '').replace(']', '')
                else:
                    matched_name = full_match_str.replace(
                        '[', '').replace(']', '')
                    matched_id = "Unknown"
            except:
                matched_name = full_match_str
                matched_id = "Unknown"

            log_to_file(
                f"👉 LLM 最終對應結果: 【 名稱: {matched_name} | 整合編號: {matched_id} 】\n")
            log_to_file("-" * 60)

            # 存入快取
            match_cache[cache_key] = {"name": matched_name, "整合編號": matched_id}

            resolved_ingredients.append({
                "original": target_name,
                "matched": matched_name,
                "整合編號": matched_id,
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
    end_recipe_num = None  # 將run_mode設為batch，再將這裡的數字改成None，就可以跑整個recipe

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
                # 新增功能：快取持久化 - 離開手動模式前，將剛才測試的紀錄存檔
                save_all_caches()
                break
            if not raw_query:
                continue

            # 🌟 步驟 0：LLM 淨化查詢詞
            clean_query = get_core_ingredient(raw_query)
            print(f"✨ LLM 淨化查詢詞: 【 {raw_query} 】 -> 【 {clean_query} 】")

            # 🌟 步驟 1：執行向量檢索
            candidates, search_method = search_candidates(
                clean_query, top_k=10)

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

        output_json_file = os.path.join(
            output_dir, 'resolved_recipes_output.json')
        output_txt_file = os.path.join(
            output_dir, 'resolved_recipes_detailed_log.txt')

        print(f"開始處理食譜比對作業 (範圍: {start_recipe_num} 到 {end_recipe_num})...")

        # 把 output_txt_file 傳進 process_recipes
        final_results = process_recipes(
            recipes_file,
            start_idx=start_recipe_num,
            end_idx=end_recipe_num,
            log_file_path=output_txt_file
        )

        with open(output_json_file, 'w', encoding='utf-8') as f:
            json.dump(final_results, f, ensure_ascii=False, indent=2)

        # 批次比對結束後，將所有新學習到的對應存檔
        save_all_caches()

        print(f"\n✅ 批次處理完成！")
        print(f"📁 JSON 結果已儲存至: {output_json_file}")
        print(f"📄 完整詳細 TXT 紀錄已儲存至: {output_txt_file}")

    else:
        print("錯誤的 RUN_MODE 設定！請設定為 'manual' 或 'batch'")
