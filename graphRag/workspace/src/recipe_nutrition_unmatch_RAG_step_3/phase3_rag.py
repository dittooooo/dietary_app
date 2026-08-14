import json
import os
from tqdm import tqdm
from openai import OpenAI
from dotenv import load_dotenv
import re
import datetime
from sentence_transformers import SentenceTransformer, util

# ==========================================
# 1. 初始化與設定區塊
# ==========================================
load_dotenv()
api_key = os.getenv("OPENAI_API_KEY")
# print("api_key :", api_key)
client = OpenAI(api_key=api_key)

# 使用您的模型
MODEL_NAME = "gpt-4.1-nano"

# 📂 請確認以下路徑是否符合您的實際環境
MISSING_INPUT_FILE = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG_step_2\data\output\missing_integration_20260426_120722.json"
LOCAL_DB_FILE = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json"

ROOT_DIR = "C:/Users/PARALELL/Desktop/code4/workspace/src/recipe_nutrition_unmatch_RAG_step_3/data/output/"
MATCHED_OUTPUT = ROOT_DIR + "phase3_rag_matched.json"
# print("MATCHED_OUTPUT :", MATCHED_OUTPUT)
PHASE4_INPUT = ROOT_DIR + "phase4_input.json"
LOG_FILE = ROOT_DIR + "phase3_rag_raw_responses.txt"

# 測試開關
ENABLE_SINGLE_TEST = True
SINGLE_TEST_INGREDIENT = "冷飲用水"

print("正在載入 Embedding 模型 (shibing624/text2vec-base-chinese)...")
embedder = SentenceTransformer('shibing624/text2vec-base-chinese')

# 全域變數
global_metadata = []
global_embeddings = None
valid_db_dict = {}

# ==========================================
# 2. 建立 RAG 向量索引庫與合法字典 (在記憶體中快速重建)
# ==========================================


def build_indices(db_filepath):
    global global_metadata, global_embeddings, valid_db_dict

    if not os.path.exists(db_filepath):
        print(f"找不到本地資料庫檔案 {db_filepath}。")
        return False

    with open(db_filepath, "r", encoding="utf-8") as f:
        local_db = json.load(f)

    global_docs = []

    def extract_info(item, category):
        if not isinstance(item, dict):
            return
        id_code = item.get("整合編號", "")
        name = item.get("樣品名稱", "")
        common_name = item.get("俗名", "")
        desc = item.get("內容物描述", "")

        invalid_ids = ["", "null", "None", "none"]
        if id_code and str(id_code).strip() not in invalid_ids and name:
            clean_id = str(id_code).strip()
            valid_db_dict[clean_id] = name

            # 建立給向量搜尋用的文本
            global_text = f"分類：{category}。名稱：{name}。別名：{common_name}。描述：{desc}"

            meta_data = {
                "id": clean_id,
                "name": name,
                "aliases": common_name,
                "category": category,
            }

            global_docs.append(global_text)
            global_metadata.append(meta_data)

    print("\n📦 正在建立全域向量索引庫與合法字典...")
    if isinstance(local_db, list):
        for item in local_db:
            extract_info(item, "未分類")
    elif isinstance(local_db, dict):
        for cat, items in local_db.items():
            if isinstance(items, list):
                for item in items:
                    extract_info(item, cat)
            elif isinstance(items, dict) and "整合編號" in items:
                extract_info(items, cat)

    # 🚀 在記憶體中快速建立 Tensor，不需依賴 ChromaDB
    global_embeddings = embedder.encode(global_docs, convert_to_tensor=True)
    print(f"✅ 索引建立完成！共 {len(global_docs)} 筆合法資料。\n")
    return True

# ==========================================
# 3. 寬鬆版 RAG 檢索 (無長度懲罰，取 Top-30)
# ==========================================


def search_top_k_candidates(query, top_k=30):
    query_emb = embedder.encode(query, convert_to_tensor=True)
    scores = util.cos_sim(query_emb, global_embeddings)[0]

    all_candidates = []
    for i, score in enumerate(scores):
        score_val = score.item()
        db_name = global_metadata[i]['name']
        db_aliases = [a.strip() for a in str(
            global_metadata[i]['aliases']).split(',') if a.strip()]

        # 基礎加分機制，不作長度懲罰
        if query == db_name or query in db_aliases:
            score_val += 0.5
        elif query in db_name or (global_metadata[i]['aliases'] and query in global_metadata[i]['aliases']):
            score_val += 0.15

        all_candidates.append((score_val, global_metadata[i]))

    all_candidates.sort(key=lambda x: x[0], reverse=True)

    # 將 Top-K 轉換為文字清單給 LLM 閱讀
    candidates_text = ""
    for idx, (s, meta) in enumerate(all_candidates[:top_k]):
        candidates_text += f"[{meta['id']}] 名稱: {meta['name']} (俗名: {meta['aliases']}) - 相似度分數: {s:.2f}\n"

    return candidates_text

# ==========================================
# 4. 讀取缺失食材與 LLM 判斷核心
# ==========================================


def load_missing_ingredients(filepath):
    """💡 修正：直接讀取 { "食材": 次數 } 的字典格式"""
    if not os.path.exists(filepath):
        return []
    with open(filepath, "r", encoding="utf-8") as f:
        data = json.load(f)

    # 如果是我們看到的 { "美乃滋": 27, "玉米筍": 26 } 格式
    if isinstance(data, dict):
        return list(data.keys())
    return []


def match_ingredient_rag(target_ingredient, candidates_text):
    """利用倒置 Prompt 結合 Top-30 候選清單解決模型失憶"""
    prompt = f"""
【候選清單 (Top-30 檢索結果)】
{candidates_text}

====================================
📢 【本次任務核心指令】
你的任務是將目標食材「 {target_ingredient} 」，與上方的【候選清單】進行配對。

【核心匹配與防護規則】
1. 優先嘗試「直白還原」：尋找最通用、最相近的常態食材。只要本質相同，字數差異不影響配對（例如：「老薑」可對應「生薑」）。
2. 嚴禁過度聯想：絕對不可因為共用單字就配對。若名單中「完全沒有」本質相同的食材，請勇敢標示 "is_matched" 為 false！

【輸出格式與嚴格限制】
1. 請「先」以純文字簡述思考過程（限50字內）。
2. 接著空一行，再輸出配對結果的純 JSON 物件。
3. ⚠️ 終極警告：JSON 內的 "original" 欄位，必須死死鎖定填寫「{target_ingredient}」，絕對不可擅自更改！

{{
  "original": "{target_ingredient}",
  "is_matched": true 或 false,
  "整合編號": "找到的編號或 null (只能填寫純英數字，不可包含中括號 [ ])",
  "樣品名稱": "找到的名稱或 null"
}}
"""
    result_str = ""
    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[{"role": "user", "content": prompt}],
            temperature=0
        )

        result_str = response.choices[0].message.content.strip()

        # 寫入 Log 保留案發現場
        with open(LOG_FILE, "a", encoding="utf-8") as log_file:
            now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_file.write(
                f"\n[{now_str}] 查詢食材：{target_ingredient}\n{result_str}\n" + "="*60 + "\n")

        # 剝除廢話，擷取 JSON
        start_idx = result_str.find('{')
        end_idx = result_str.rfind('}')
        if start_idx != -1 and end_idx != -1:
            result_str = result_str[start_idx:end_idx+1]

        result_str = re.sub(r',\s*([\]}])', r'\1', result_str)
        return json.loads(result_str)

    except Exception as e:
        print(f"\n[錯誤] 匹配 '{target_ingredient}' 時發生異常: {e}")
        return None

# ==========================================
# 5. 主程式執行
# ==========================================


def main():
    print("🚀 開始執行 Phase 3: RAG 專屬匹配模式...")
    if not build_indices(LOCAL_DB_FILE):
        return

    if ENABLE_SINGLE_TEST:
        print(f"\n==========================================")
        print(f"🔍 [單筆測試模式] 正在尋找食材：「{SINGLE_TEST_INGREDIENT}」")
        print(f"==========================================")
        candidates_text = search_top_k_candidates(
            SINGLE_TEST_INGREDIENT, top_k=30)
        print("\n🔎 RAG 檢索出以下候選名單 (節錄前 5 筆看狀況)：\n" +
              "\n".join(candidates_text.split('\n')[:5]))

        result = match_ingredient_rag(SINGLE_TEST_INGREDIENT, candidates_text)

        if result:
            print("\n🤖 [AI 原始回傳結果]:")
            print(json.dumps(result, ensure_ascii=False, indent=2))

            invalid_ids = ["", "null", "None", "none"]
            if result.get("is_matched") is True:
                matched_id = result.get("整合編號")
                if matched_id and isinstance(matched_id, str):
                    matched_id = matched_id.replace(
                        "[", "").replace("]", "").strip()

                if matched_id and str(matched_id).strip() not in invalid_ids:
                    if str(matched_id).strip() in valid_db_dict:
                        print(
                            f"\n✅ [系統驗證成功] 本地資料庫確實有: [{matched_id}] {valid_db_dict[str(matched_id).strip()]}")
                    else:
                        print(f"\n❌ [系統攔截幻覺] 模型發明了不存在的編號 '{matched_id}'！")
                else:
                    print(f"\n❌ [系統攔截無效值] 模型回傳了無效編號 '{matched_id}'")
            else:
                print("\n⚠️ [結論] 模型判定本地資料庫沒有合適的配對。")
        return

    # 批次處理
    missing_ingredients = load_missing_ingredients(MISSING_INPUT_FILE)
    print(f"\n共載入 {len(missing_ingredients)} 筆待匹配食材。")
    if not missing_ingredients:
        return

    matched_results = []
    leftover_ingredients = []

    for ing in tqdm(missing_ingredients, desc="Phase 3 RAG 匹配進度", unit="筆"):
        candidates_text = search_top_k_candidates(ing, top_k=30)
        result = match_ingredient_rag(ing, candidates_text)

        is_valid_match = False
        if result and result.get("is_matched") is True:
            matched_id = result.get("整合編號")
            invalid_ids = ["", "null", "None", "none"]

            if matched_id and isinstance(matched_id, str):
                matched_id = matched_id.replace(
                    "[", "").replace("]", "").strip()
                result["整合編號"] = matched_id

            if matched_id and str(matched_id).strip() not in invalid_ids:
                if str(matched_id).strip() in valid_db_dict:
                    is_valid_match = True

        if is_valid_match:
            matched_results.append(result)
        else:
            leftover_ingredients.append(ing)

    with open(MATCHED_OUTPUT, "w", encoding="utf-8") as f:
        json.dump(matched_results, f, ensure_ascii=False, indent=2)
    with open(PHASE4_INPUT, "w", encoding="utf-8") as f:
        json.dump(leftover_ingredients, f, ensure_ascii=False, indent=2)

    print("\n✅ Phase 3 RAG 作業結束！")
    print(f"🎉 成功找回: {len(matched_results)} 筆 (儲存至 {MATCHED_OUTPUT})")
    print(f"⚠️ 需聯網食材: {len(leftover_ingredients)} 筆 (儲存至 {PHASE4_INPUT})")


if __name__ == "__main__":
    main()
