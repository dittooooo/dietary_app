import json
import os
from tqdm import tqdm
from openai import OpenAI
from dotenv import load_dotenv
import re
import datetime

# 載入 .env 中的變數
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# ==========================================
# ⚙️ 測試與執行設定區塊
# ==========================================
ENABLE_SINGLE_TEST = True        # 🟢 切換模式：設為 True 進入單筆測試，設為 False 執行批次處理
# 📝 手動測試的食材名稱 (僅在 ENABLE_SINGLE_TEST 為 True 時有效)
SINGLE_TEST_INGREDIENT = "冷水"  # 棕櫚糖, 大阪燒醬, 廣達香香辣鮪魚醬, 牛肉湯, 無調味堅果, 乾巴西利碎, 豬五花, 無糖優格

# ==========================================
# 📂 檔案路徑設定區塊 (請替換為您的實際路徑)
# ==========================================
MISSING_INPUT_FILE = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG_step_3\data\input\missing_integration_20260426_120722.json"
LOCAL_DB_FILE = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json"

timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
MATCHED_OUTPUT = f"C:/Users/PARALELL/Desktop/code4/workspace/src/recipe_nutrition_unmatch_RAG_step_3/data/output/phase3_matched_{timestamp}.json"
PHASE4_INPUT = f"C:/Users/PARALELL/Desktop/code4/workspace/src/recipe_nutrition_unmatch_RAG_step_3/data/output/phase4_matched_{timestamp}.json"


def load_missing_ingredients(filepath):
    """讀取待處理的未知食材清單，並去除重複項目"""
    if not os.path.exists(filepath):
        print(f"找不到檔案 {filepath}，請確認路徑。")
        return []

    with open(filepath, "r", encoding="utf-8") as f:
        data = json.load(f)

    unique_ingredients = {}
    if isinstance(data, list) and len(data) > 0 and isinstance(data[0], dict) and "recipe_id" in data[0]:
        for recipe in data:
            for ing in recipe.get("resolved_ingredients", []):
                ing_name = ing.get("original")
                if ing_name:
                    unique_ingredients[ing_name] = True
    else:
        for name in data:
            unique_ingredients[name] = True

    return list(unique_ingredients.keys())


def build_local_db_candidates(db_filepath):
    """提取候選清單，同時回傳一個「合法編號字典」供後續防呆驗證"""
    if not os.path.exists(db_filepath):
        print(f"找不到本地資料庫檔案 {db_filepath}。")
        return "", {}

    with open(db_filepath, "r", encoding="utf-8") as f:
        local_db = json.load(f)

    candidates = []
    valid_db_dict = {}

    def extract_info(item):
        if not isinstance(item, dict):
            return
        id_code = item.get("整合編號", "")
        name = item.get("樣品名稱", "")
        common_name = item.get("俗名", "")

        # 💡 防護：拒絕任何形式的 null 或 None 字串
        invalid_ids = ["", "null", "None", "none"]

        if id_code and str(id_code).strip() not in invalid_ids and name:
            valid_db_dict[str(id_code).strip()] = name

            display_text = f"[{id_code}] {name}"
            if common_name and common_name.strip() not in ["", "None", "null"]:
                display_text += f" (俗名: {common_name})"
            candidates.append(display_text)

    if isinstance(local_db, list):
        for item in local_db:
            extract_info(item)
    elif isinstance(local_db, dict):
        for category, items in local_db.items():
            if isinstance(items, list):
                for item in items:
                    extract_info(item)
            elif isinstance(items, dict) and "整合編號" in items:
                extract_info(items)

    return "\n".join(candidates), valid_db_dict


def match_ingredient_internally(target_ingredient, db_candidate_text):
    """利用「倒置 Prompt」解決小模型的失憶與幻覺問題"""

    prompt = f"""
【本地營養資料庫候選名單】
{db_candidate_text}

====================================
📢 【本次任務核心指令】
你的任務是將目標食材「 {target_ingredient} 」，與上方的【本地營養資料庫候選名單】進行配對。

【核心匹配與防護規則】
1. 優先嘗試「直白還原」：尋找最通用、最相近的常態食材。
2. 嚴禁過度聯想：絕對不可因為共用單一字元就進行錯誤配對。
3. 寧缺勿濫：如果上方名單中「完全沒有」本質相同的食材，請勇敢標示 "is_matched" 為 false，不要強迫配對！

【輸出格式與嚴格限制】
1. 請「先」以純文字簡述你的判斷標準與思考過程（限50字內）。
2. 接著空一行，再輸出配對結果的純 JSON 物件。
3. ⚠️ 終極警告：JSON 內的 "original" 欄位，你必須死死鎖定填寫「{target_ingredient}」，絕對不可擅自更改為其他食材名稱！請嚴格遵守下方結構：

{{
  "original": "{target_ingredient}",
  "is_matched": true 或 false,
  "整合編號": "找到的編號或 null (只能填寫純英數字，不可包含中括號 [ ])",
  "樣品名稱": "找到的名稱或 null"
}}
"""
    result_str = ""
    try:
        response = client.responses.create(
            model="gpt-4.1-nano",
            input=prompt
        )

        result_str = response.output_text

        # ==========================================
        # 📝 寫入原始 Log，保留案發現場
        # ==========================================
        log_filepath = "phase3_raw_responses.txt"
        with open(log_filepath, "a", encoding="utf-8") as log_file:
            now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_file.write(f"\n[{now_str}] 查詢食材：{target_ingredient}\n")
            log_file.write(result_str)
            log_file.write("\n" + "="*60 + "\n")

        # ==========================================
        # 🛡️ 安全網：擷取 JSON 並剝除多餘逗號
        # ==========================================
        start_idx = result_str.find('{')
        end_idx = result_str.rfind('}')
        if start_idx != -1 and end_idx != -1:
            result_str = result_str[start_idx:end_idx+1]

        result_str = re.sub(r',\s*([\]}])', r'\1', result_str)
        return json.loads(result_str)

    except Exception as e:
        print(f"\n[錯誤] 匹配 '{target_ingredient}' 時發生異常: {e}")
        if result_str:
            print("\n--- 🕵️ 模型實際回傳的損壞內容 ---")
            print(result_str)
            print("----------------------------------\n")
        return None


def main():
    print("🚀 開始執行 Phase 3: 本地資料庫重新匹配 (最終防護版)...")

    print("📦 正在提取本地資料庫並建立合法驗證字典...")
    db_candidate_text, valid_db_dict = build_local_db_candidates(LOCAL_DB_FILE)
    if not db_candidate_text:
        return

    # ==========================================
    # 🔍 單筆測試模式邏輯
    # ==========================================
    if ENABLE_SINGLE_TEST:
        print(f"\n==========================================")
        print(f"🔍 [單筆測試模式] 正在尋找食材：「{SINGLE_TEST_INGREDIENT}」")
        print(f"==========================================")

        result = match_ingredient_internally(
            SINGLE_TEST_INGREDIENT, db_candidate_text)

        if result:
            print("\n🤖 [AI 原始回傳結果]:")
            print(json.dumps(result, ensure_ascii=False, indent=2))

            # 模擬 Python 查驗機制
            invalid_ids = ["", "null", "None", "none"]
            if result.get("is_matched") is True:
                matched_id = result.get("整合編號")

                # 💡 Python 防呆脫殼：剝除可能被 AI 誤加的中括號
                if matched_id and isinstance(matched_id, str):
                    matched_id = matched_id.replace(
                        "[", "").replace("]", "").strip()
                    result["整合編號"] = matched_id  # 把乾淨的編號寫回 result 裡

                # 💡 Python 終極驗證：黑名單 + 字典查核
                if matched_id and str(matched_id).strip() not in invalid_ids:
                    if str(matched_id).strip() in valid_db_dict:
                        print(
                            f"\n✅ [系統驗證成功] 本地資料庫確實有: [{matched_id}] {valid_db_dict[str(matched_id).strip()]}")
                    else:
                        print(f"\n❌ [系統攔截幻覺] 模型發明了不存在的編號 '{matched_id}'！")
                else:
                    print(f"\n❌ [系統攔截無效值] 模型判定成功，卻回傳了無效編號 '{matched_id}'")
            else:
                print("\n⚠️ [結論] 模型判定本地資料庫沒有合適的配對。")
        else:
            print("\n❌ 匹配失敗或發生異常。")

        print("\n💡 單筆測試結束。若要執行批次處理，請將 ENABLE_SINGLE_TEST 設為 False。")
        return

    # ==========================================
    # 🚀 批次處理模式邏輯
    # ==========================================
    missing_ingredients = load_missing_ingredients(MISSING_INPUT_FILE)
    print(f"\n共載入 {len(missing_ingredients)} 筆待匹配食材。")
    if not missing_ingredients:
        return

    print("開始進行智能匹配與雙重驗證！\n")

    matched_results = []
    leftover_ingredients = []

    for ing in tqdm(missing_ingredients, desc="Phase 3 匹配進度", unit="筆"):
        result = match_ingredient_internally(ing, db_candidate_text)

        if result:
            is_valid_match = False
            invalid_ids = ["", "null", "None", "none"]

            if result.get("is_matched") is True:
                matched_id = result.get("整合編號")

                # 💡 Python 防呆脫殼：剝除可能被 AI 誤加的中括號 (解決 [R5100901] 錯誤)
                if matched_id and isinstance(matched_id, str):
                    matched_id = matched_id.replace(
                        "[", "").replace("]", "").strip()
                    result["整合編號"] = matched_id  # 把乾淨的編號寫回 result 裡

                # 💡 Python 終極驗證：黑名單 + 字典查核
                if matched_id and str(matched_id).strip() not in invalid_ids:
                    if str(matched_id).strip() in valid_db_dict:
                        is_valid_match = True
                    else:
                        print(
                            f"\n⚠️ 系統攔截幻覺：模型試圖將 '{ing}' 配對至不存在的編號 '{matched_id}'")
                else:
                    print(f"\n⚠️ 系統攔截無效值：模型判定成功，卻回傳了無效編號 '{matched_id}'")

            if is_valid_match:
                # 驗證成功，移除思考過程以節省 JSON 檔案空間
                if "AI_思考過程" in result:
                    del result["AI_思考過程"]
                matched_results.append(result)
            else:
                # 被攔截的幻覺、無效值，或真的找不到的食材，統一送交 Phase 4 聯網處理
                leftover_ingredients.append(ing)
        else:
            leftover_ingredients.append(ing)

    with open(MATCHED_OUTPUT, "w", encoding="utf-8") as f:
        json.dump(matched_results, f, ensure_ascii=False, indent=2)

    with open(PHASE4_INPUT, "w", encoding="utf-8") as f:
        json.dump(leftover_ingredients, f, ensure_ascii=False, indent=2)

    print("\n✅ Phase 3 作業結束！")
    print(f"🎉 成功且精準找回: {len(matched_results)} 筆 (已儲存至 {MATCHED_OUTPUT})")
    print(f"⚠️ 真正需聯網的食材: {len(leftover_ingredients)} 筆 (已儲存至 {PHASE4_INPUT})")


if __name__ == "__main__":
    main()
