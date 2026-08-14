import json
import os
from tqdm import tqdm
from openai import OpenAI
from dotenv import load_dotenv
import re  # <--- 請確保有補上這一行
import datetime  # 新增：用於產生 Log 的時間戳記

# 載入 .env 中的變數 (包含 OPENAI_API_KEY)
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


INPUT_FILE = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG_step_2\data\input\20260424_124834\resolved_recipes_output.json"
INPUT_FILE_2 = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json"
CACHE_FILE = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG_step_2\data\output\ingredient_cache.json"

# ==========================================
# ⚙️ 測試與執行設定區塊
# ==========================================
TEST_SINGLE_INGREDIENT = "青江菜"  # 單筆測試，填寫名稱如 "豬後腿肉"，留空則進入批次模式
TEST_LIMIT = None               # 小範圍測試，設為 0 或 None 則處理全部
# ==========================================


def get_unique_missing_ingredients(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        data = json.load(f)

    # 改用 dict 來保留插入順序 (Python 3.7+ 特性)
    unique_ingredients = {}
    for recipe in data:
        for ing in recipe.get("resolved_ingredients", []):
            if ing.get("整合編號") in ["None", None]:
                ing_name = ing.get("original")
                # 如果這個食材名稱還沒被加入過，才加進 dict 中
                if ing_name not in unique_ingredients:
                    unique_ingredients[ing_name] = True

    # 將 dict 的鍵值 (keys) 轉為 list，這會完美保留它們第一次出現的順序
    return list(unique_ingredients.keys())


def load_cache(filepath):
    if os.path.exists(filepath):
        with open(filepath, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_cache(filepath, cache_data):
    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(cache_data, f, ensure_ascii=False, indent=2)


def query_openai_responses_api(ingredient_name, custom_id):
    """依照官方最新 Responses API 語法進行聯網查詢 (完整營養素版 + 自動防呆修復 + Log保留模型解釋)"""

    prompt = f"""
你是一個專業的台灣食品營養學專家。請使用 Web 搜尋工具查詢「台灣食品營養成分資料庫」的最新且完整數據。

【重要配對規則】
請採取「直白還原」的邏輯進行配對，直接尋找最相近、最通用的常態食材，切勿因為字數長度差異而改變選擇。

【整合編號規則】
請忽略資料庫中原有的整合編號。本次查詢的指定整合編號為「{custom_id}」，請直接將此編號填入回傳的 JSON 中。

【資料出處規則】
在「資料出處」欄位中，請僅提供該筆資料來源的「網址 (URL)」，不要包含任何額外的文字敘述、標題或說明。

【輸出格式與補充說明要求】
1. 請務必「先」輸出完整的 JSON 物件。請嚴格遵守以下所有欄位名稱，不可遺漏、不可將結果包裝在食材名稱下，且最後一個屬性結尾絕對不可加上逗號。
2. 在 JSON 物件輸出完畢後，請空一行，並加上「說明：」，簡要描述你的資料來源選擇、以及為何某些欄位填寫 null 的判斷依據。為了節省資源，這段說明請直接取其精華，嚴格限制在 250 字以內。
3. ⚠️ 極度重要：在你的「說明」文字段落中，絕對不可以使用任何大括號「'{'」或「'}'」，以免破壞系統解析。

必須回傳的 JSON 結構如下（請將數值替換為查詢到的「{ingredient_name}」實際數據）：
{{
"整合編號": "{custom_id}",
"食品分類": "",
"樣品名稱": "",
"俗名": "",
"熱量(kcal)": null,
"水分(g)": null,
"粗蛋白(g)": null,
"粗脂肪(g)": null,
"飽和脂肪(g)": null,
"反式脂肪(g)": null,
"膽固醇(mg)": null,
"總碳水化合物(g)": null,
"膳食纖維(g)": null,
"糖質總量(g)": null,
"鈉(mg)": null,
"鉀(mg)": null,
"鈣(mg)": null,
"鎂(mg)": null,
"磷(mg)": null, 
"鐵(mg)": null,
"鋅(mg)": null,
"維生素A總量(IU)": null,
"維生素B12(ug)": null,
"葉酸(ug)": null,
"維生素C(mg)": null,
"維生素D總量(IU)": null,
"維生素E總量(mg)": null,
"資料出處": ""
}}
"""
    result_str = ""
    try:
        response = client.responses.create(
            model="gpt-4o-mini",  # gpt-4o
            tools=[{"type": "web_search"}],
            input=prompt
        )

        result_str = response.output_text

        # ==========================================
        # 💡 第一步：將「包含模型解釋」的原始回傳內容寫入 Log 檔案
        # 這樣您的 txt 檔就會保留完整的 "說明：" 段落
        # ==========================================
        log_filepath = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG_step_2\data\output\api_raw_responses.txt"
        with open(log_filepath, "a", encoding="utf-8") as log_file:
            now_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_file.write(
                f"\n[{now_str}] 查詢食材：{ingredient_name} (整合編號: {custom_id})\n")
            log_file.write(result_str)
            log_file.write("\n" + "="*60 + "\n")

        # ==========================================
        # 💡 第二步：暴力擷取大括號 { } 範圍，切斷前後的說明文字
        # 程式執行到這裡，說明文字就會被無情拋棄，只把 JSON 送給主程式
        # ==========================================
        start_idx = result_str.find('{')
        end_idx = result_str.rfind('}')
        if start_idx != -1 and end_idx != -1:
            result_str = result_str[start_idx:end_idx+1]

        # 清理可能夾帶的 Markdown 標記
        if "```json" in result_str:
            result_str = result_str.replace(
                "```json", "").replace("```", "").strip()
        elif "```" in result_str:
            result_str = result_str.replace("```", "").strip()

        # 自動修復 JSON 結尾多餘的逗號
        result_str = re.sub(r',\s*([\]}])', r'\1', result_str)

        parsed_json = json.loads(result_str)

        # 自動剝除多餘的外層包裝
        if "整合編號" not in parsed_json and len(parsed_json) == 1:
            first_key = list(parsed_json.keys())[0]
            if isinstance(parsed_json[first_key], dict):
                parsed_json = parsed_json[first_key]

        return parsed_json

    except Exception as e:
        print(f"\n[錯誤] 查詢 '{ingredient_name}' 時發生異常: {e}")
        if result_str:
            print("\n--- 🕵️ 以下為模型實際回傳的錯誤內容，供除錯參考 ---")
            print(result_str)
            print("--------------------------------------------------\n")
        else:
            print("⚠️ API 未回傳任何文字或發生連線異常。")
        return None


def main():
    # 載入快取
    cache = load_cache(CACHE_FILE)

    # 動態計算目前要從哪一個 custom_ ID 開始編號
    max_custom_idx = 4  # 預設從 4 開始，這樣下一個就會是 5
    for data in cache.values():
        val = data.get("整合編號", "")
        if val and val.startswith("custom_"):
            try:
                # 提取 custom_ 後面的數字
                idx = int(val.split("_")[1])
                if idx > max_custom_idx:
                    max_custom_idx = idx
            except:
                pass

    current_custom_index = max_custom_idx + 1

    # 單筆測試模式
    if TEST_SINGLE_INGREDIENT:
        print(f"\n🔍 [單筆測試] 正在查詢：「{TEST_SINGLE_INGREDIENT}」...")
        custom_id = f"custom_{current_custom_index}"
        result = query_openai_responses_api(TEST_SINGLE_INGREDIENT, custom_id)
        if result:
            result["整合編號"] = custom_id  # 強制覆寫雙重保障
            print("\n✅ 查詢結果：")
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print("\n❌ 查詢失敗。")
        return

    # 批次處理模式
    missing_ingredients = get_unique_missing_ingredients(INPUT_FILE)

    to_query = [ing for ing in missing_ingredients if ing not in cache]
    print(
        f"總共需要處理 {len(missing_ingredients)} 筆 / 扣除快取後，實際需呼叫 API 查詢 {len(to_query)} 筆食材。")
    print(f"👉 本次將從編號 custom_{current_custom_index} 開始生成。")

    if not to_query:
        print("所有食材皆已查詢完畢！")
        return

    # 小範圍測試限制
    if TEST_LIMIT and TEST_LIMIT > 0:
        to_query = to_query[:TEST_LIMIT]
        print(f"⚠️ [測試模式] 已限制本次僅處理前 {TEST_LIMIT} 筆。")

    for ing in tqdm(to_query, desc="處理進度", unit="筆"):
        custom_id = f"custom_{current_custom_index}"
        result = query_openai_responses_api(ing, custom_id)

        if result:
            result["整合編號"] = custom_id  # 【雙重保障】無視模型亂填，程式層級強制覆蓋為正確的編號
            cache[ing] = result
            save_cache(CACHE_FILE, cache)
            current_custom_index += 1      # 成功處理後，編號 +1 進入下一波

    print("\n✅ 作業結束！結果已儲存至", CACHE_FILE)


if __name__ == "__main__":
    main()
