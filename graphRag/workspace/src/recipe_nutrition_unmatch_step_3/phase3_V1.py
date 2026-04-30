import json
import os
from tqdm import tqdm
from openai import OpenAI
from dotenv import load_dotenv
import re

# 載入 .env 中的變數
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# ==========================================
# 📂 檔案路徑設定區塊 (請替換為您的實際路徑)
# ==========================================
MISSING_INPUT_FILE = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG_step_3\data\input\missing_integration_20260426_120722.json"
LOCAL_DB_FILE = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json"

# Phase 3 的輸出結果
MATCHED_OUTPUT = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG_step_3\data\output\phase3_matched.json"      # 成功在本地找回來的食材
# 真的找不到，需要留給 Phase 4 聯網的食材
PHASE4_INPUT = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG_step_3\data\output\phase4_input.json"
# ==========================================


def load_missing_ingredients(filepath):
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
    valid_db_dict = {}  # 儲存所有合法的 整合編號 -> 樣品名稱

    def extract_info(item):
        if not isinstance(item, dict):
            return
        id_code = item.get("整合編號", "")
        name = item.get("樣品名稱", "")
        common_name = item.get("俗名", "")

        if id_code and name:
            valid_db_dict[id_code] = name  # 登錄合法名單

            display_text = f"[{id_code}] {name}"
            if common_name and common_name.strip() not in ["", "None", "null"]:
                display_text += f" (俗名: {common_name})"
            candidates.append(display_text)

    # 適應多種 JSON 結構
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
    """加入 CoT 思考過程與嚴格防護規則的匹配"""

    prompt = f"""
你是一個極度嚴謹的資料庫匹配助手。你的任務是將「目標食材」，與下方【本地營養資料庫候選名單】進行配對。

【核心匹配與防護規則】
1. 優先嘗試「直白還原」：尋找最通用、最相近的常態食材（例如：「老薑」對應「生薑」）。
2. 嚴禁過度聯想：絕對不可因為共用單一字元就進行錯誤配對。例如找「水」絕對不可配對「香水芒果」；找「豬肉粉」絕對不可配對「生豬肉」。食材的「物理與烹飪本質」必須相同。
3. 寧缺勿濫：如果在候選名單中「完全沒有」本質相同的食材，請勇敢標示 "is_matched" 為 false，不要強迫配對！

【輸出格式】
請務必以純 JSON 格式回覆，不可加上任何 Markdown 標記，結構如下：
{{
  "AI_思考過程": "請簡述你的判斷標準，確認兩者本質是否一致（限50字）",
  "original": "{target_ingredient}",
  "is_matched": true 或 false,
  "整合編號": "找到的編號或 null",
  "樣品名稱": "找到的名稱或 null"
}}

【本地營養資料庫候選名單】
{db_candidate_text}
"""
    try:
        response = client.responses.create(
            model="gpt-4o-mini",
            input=prompt
        )

        result_str = response.output_text

        start_idx = result_str.find('{')
        end_idx = result_str.rfind('}')
        if start_idx != -1 and end_idx != -1:
            result_str = result_str[start_idx:end_idx+1]

        result_str = re.sub(r',\s*([\]}])', r'\1', result_str)
        return json.loads(result_str)

    except Exception as e:
        print(f"\n[錯誤] 匹配 '{target_ingredient}' 時發生異常: {e}")
        return None


def main():
    print("🚀 開始執行 Phase 3: 本地資料庫重新匹配 (嚴格防護版)...")

    missing_ingredients = load_missing_ingredients(MISSING_INPUT_FILE)
    print(f"共載入 {len(missing_ingredients)} 筆待匹配食材。")
    if not missing_ingredients:
        return

    print("正在建立候選清單與合法驗證字典...")
    db_candidate_text, valid_db_dict = build_local_db_candidates(LOCAL_DB_FILE)
    if not db_candidate_text:
        return

    print("開始進行智能匹配與雙重驗證！")

    matched_results = []
    leftover_ingredients = []

    for ing in tqdm(missing_ingredients, desc="Phase 3 匹配進度", unit="筆"):
        result = match_ingredient_internally(ing, db_candidate_text)

        if result:
            # ==========================================
            # 💡 Python 查驗機制：攔截模型的幻覺與硬拗
            # ==========================================
            is_valid_match = False

            if result.get("is_matched") is True:
                matched_id = result.get("整合編號")

                # 檢查這個 ID 是不是真的存在於本地資料庫
                if matched_id in valid_db_dict:
                    is_valid_match = True
                else:
                    # 模型發明了不存在的 ID，直接判定為失敗
                    print(
                        f"\n⚠️ 系統攔截幻覺：模型試圖將 '{ing}' 配對至不存在的編號 '{matched_id}'")

            # 根據查驗結果進行分流
            if is_valid_match:
                # 移除思考過程以節省儲存空間
                if "AI_思考過程" in result:
                    del result["AI_思考過程"]
                matched_results.append(result)
            else:
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
