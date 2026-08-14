"""
程式名稱: 營養成分查詢系統 (NutritionQueryTool)
版本: V5 (Full Context Contextual Alignment)
說明:
直接使用 LLM 的大 Context Window 功能，將完整資料庫 (2180筆) 餵入，
配合食譜名稱與其他食材的上下文進行推論，尋找最精確或最適當的替代食材。
"""

import json
import os
import re
import difflib
from dotenv import load_dotenv
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

load_dotenv()

try:
    from openai import OpenAI
except ImportError:
    print("請先安裝 openai 套件: pip install openai")
    exit()

# ---------------- 配置設定 ----------------
API_KEY = "ollama" 
BASE_URL = "http://localhost:11434/v1" 
MODEL_NAME = "gemma3:4b" # gemma4:e4b, gemma3:4b
# ----------------------------------------

client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

# Ollama 的 OpenAI 相容 API 對 `response_format`/tools 支援不一，
# 部分模型（例如 gemma3:4b）會因為「工具」相關欄位而回 400。
USE_OLLAMA = isinstance(BASE_URL, str) and ("localhost:11434" in BASE_URL or "127.0.0.1:11434" in BASE_URL)

class NutritionQueryToolContextual:
    def __init__(self, filepath):
        self.filepath = filepath
        self.db = self._load_nutrition_data(filepath)
        
        if self.db:
            self.available_names = list(self.db.keys())
            self.synonym_mapping = {}
            # 建立包含分類的提示字串，供 LLM 參考
            items_list = []
            for name, info in self.db.items():
                category = info.get("食品分類", "未知")
                common_name = info.get("俗名")
                if common_name:
                    # 分割俗名並存入映射表
                    c_refs = re.split(r'[,，、]', common_name)
                    for c_name in c_refs:
                        c_name_clean = re.sub(r'\(.*?\)', '', c_name).strip()
                        c_name_clean = re.sub(r'".*?"', '', c_name_clean).strip()
                        if c_name_clean and c_name_clean not in self.synonym_mapping:
                            self.synonym_mapping[c_name_clean] = name
                            
                    items_list.append(f"{name} (俗名:{common_name}) [{category}]")
                else:
                    items_list.append(f"{name} [{category}]")
            self.db_items_str = "、".join(items_list)
        else:
            self.available_names = []
            self.synonym_mapping = {}
            self.db_items_str = ""

    def _load_nutrition_data(self, filepath):
        try:
            with open(filepath, 'r', encoding='utf-8') as file:
                data = json.load(file)
            name_index = {}
            for item in data:
                name = item.get("樣品名稱")
                if name:
                    name_index[name] = item
            return name_index
        except Exception as e:
            print(f"載入資料庫發生錯誤：{e}")
            return None

    def ask_llm_for_best_match(self, target_ingredient, recipe_name="無", other_ingredients="無", verbose=False):
        if not self.available_names:
            if verbose: print("錯誤：資料庫尚未成功載入。")
            return {"name": None, "reason": "資料庫尚未成功載入"}

        prompt = f"""
你是一個專業的營養學、烹飪專家與資料庫檢索助手。

以下是台灣食品營養資料庫中所有的合法食材項目（格式為「名稱 (俗名:如果有) [分類]」，共約兩千多筆）：
【資料庫清單開始】
{self.db_items_str}
【資料庫清單結束】

現在我們正在處理一道食譜的食材標準化轉換，上下文資訊如下：
- 食譜名稱：{recipe_name}
- 其他食材：{other_ingredients}

請在這個食譜的烹飪上下文中，為以下「目標食材」從上述選項中找出最適合的唯一對應項目：
【目標食材】：{target_ingredient}

【重要挑選準則】：
1. 你「必須、絕對」從資料庫清單中挑選出一個「最適合」在該食譜中作為替代的項目。絕對不允許回傳 null！
2. 發揮常識與烹飪相似性：即使資料庫沒賣一模一樣的原料，你也必須找一個烹飪功能、營養成分最接近的「替代品」。例如：若目標是「香蕉」，你必須選擇「北蕉平均值」；若目標是「無鹽奶油」，你必須選擇「奶油(固態,不加鹽)」；若目標是「砂糖」，你可以選擇「紅砂糖」或「冰糖」；若目標是「蕃茄糊」，你必須選擇「蕃茄醬」；若目標是「泡打粉」或「膨脹劑」，你必須選擇「酵母粉」；若目標是「起司絲」或「披薩起士絲」，你應該選擇「刨絲乾酪」；若目標是「水」，你可以選擇「高湯塊(排骨)」或最接近的湯底。
3. 容忍不完美的逼近：**絕對不能寧缺勿濫**，即使該選項只是有點沾邊，只要它是整個資料庫 2180 個選項中最接近的，你就必須選它。
4. 【嚴格限制】：回傳的 `name` 欄位必須「一字不漏地複製」清單中最前面的官方名稱！絕對不可包含我們加上去的 `(俗名:XXX)` 與 `[分類]`。
   - ❌ 錯誤範例：如果目標是「香蕉」，你推論出「北蕉平均值」，卻回傳 "name": "香蕉"
   - ✅ 正確範例：如果目標是「香蕉」，你推論出「北蕉平均值」，必須回傳 "name": "北蕉平均值"
   - ❌ 錯誤範例：如果目標是「泡打粉」，你推論出「酵母粉」，卻回傳 "name": "泡打粉"
   - ✅ 正確範例：如果目標是「泡打粉」，你推論出「酵母粉」，必須回傳 "name": "酵母粉"
   請確認你回傳的 name 原封不動地來自於我剛剛發給你的資料庫清單！絕對不要把你自己的目標食材名稱硬塞進 name 裡！

請一律以合法的 JSON 格式回傳（不可加 Markdown block）：
{{
  "name": "你挑選的真實官方名稱",
  "reason": "你的推論與選擇理由",
  "confidence": 數字 (0-100，表示你認為這個替代品在營養與常識上的貼近程度)
}}
"""
        
        if verbose:
            print(f"🧠 [混合檢索中] 正在交由 LLM 全庫對比目標食材「{target_ingredient}」（食譜：{recipe_name}）...")
        
        # 內嵌 retry 邏輯，確保只有 API 呼叫部分會重試
        @retry(
            stop=stop_after_attempt(5),
            wait=wait_exponential(multiplier=1, min=4, max=60),
            retry=retry_if_exception_type((Exception)), # 這裡可以更精細，但先捕捉大類
            reraise=True
        )
        def _call_openai():
            kwargs = dict(
                model=MODEL_NAME,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.0,
            )
            if not USE_OLLAMA:
                kwargs["response_format"] = {"type": "json_object"}
            response = client.chat.completions.create(**kwargs)
            return response.choices[0].message.content.strip()

        result_text = _call_openai()
        result = json.loads(result_text)
        
        name = result.get("name")
        reason = result.get("reason", "無推斷理由")
        
        if name:
            # 程式端清理，確保 LLM 誤傳 [分類] 或 (俗名:...) 時被拔除
            name = re.sub(r'\s*\[.*?\]$', '', name).strip()
            name = re.sub(r'\s*\(俗名:.*?\)$', '', name).strip()
            result["name"] = name
            
            if name not in self.db:
                resolved_name = None
                
                # 1. 檢查是否精準命中俗名
                if name in self.synonym_mapping:
                    resolved_name = self.synonym_mapping[name]
                    if verbose:
                        print(f"🔧 自動修正：LLM 回傳「{name}」，命中俗名對應至「{resolved_name}」")
                
                # 2. 尋找「完全包含」這個詞的官方名稱 (例如 豬絞肉 包含於 豬絞肉平均值)
                if not resolved_name:
                    substring_matches = [db_name for db_name in self.available_names if name in db_name]
                    if substring_matches:
                        resolved_name = min(substring_matches, key=len)
                        if verbose:
                            print(f"🔧 自動修正：LLM 回傳「{name}」，以子字串匹配對應至「{resolved_name}」")
                
                # 3. 如果以上都沒有，使用 difflib
                if not resolved_name:
                    all_possible_keys = self.available_names + list(self.synonym_mapping.keys())
                    matches = difflib.get_close_matches(name, all_possible_keys, n=1, cutoff=0.6)
                    if matches:
                        matched_key = matches[0]
                        # 如果配對到的是俗名，轉換成官方名稱
                        resolved_name = self.synonym_mapping.get(matched_key, matched_key)
                        if verbose:
                            print(f"🔧 自動修正：LLM 回傳「{name}」，經模糊比對「{matched_key}」對應至「{resolved_name}」")
                
                if resolved_name:
                    result["name"] = resolved_name
                else:
                    if verbose:
                        print(f"⚠️ LLM 回傳了不存在的項目：「{name}」，自動標記為 None")
                    return {"name": None, "reason": f"原始回傳了不存在的名稱：{name}，理由：{reason}", "confidence": 0}
            
        return result

    def get_nutrition_info(self, sample_name):
        return self.db.get(sample_name)


if __name__ == "__main__":
    file_name = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch\data\input\nutrition_data.json"
    tool = NutritionQueryToolContextual(file_name)
    
    # --- 切換開關 ---
    MANUAL_MODE = True  # True: 手動輸入模式, False: 測試模式
    # --------------

    if MANUAL_MODE:
        print("\n" + "="*50)
        print("🚀 進入手動查詢模式 (Nutrition V5 - Contextual)")
        print("提示：您可以直接輸入食材名稱，或在隨後提供食譜上下文以獲得更精確的匹配。")
        print("="*50)
        
        while True:
            target = input("\n請輸入你想查詢的食材名稱 (輸入 'q' 離開): ").strip()
            if target.lower() == 'q': break
            if not target: continue
            
            recipe = input("請輸入所屬食譜名稱 (選填，直接按 Enter 跳過): ").strip() or "無"
            others = input("請輸入其他食材 (選填，以逗號分隔，直接按 Enter 跳過): ").strip() or "無"
            
            match = tool.ask_llm_for_best_match(target, recipe, others, verbose=True)
            
            if match and match.get('name'):
                print("\n" + "✨" * 15)
                print(f"✅ 匹配名稱：{match.get('name')}")
                print(f"💡 挑選理由：{match.get('reason')}")
                print(f"📊 信心指數：{match.get('confidence', 'N/A')}")
                print("✨" * 15)
            else:
                print("\n❌ 無法找到合適的匹配項目。")
    else:
        # 測試模式
        test_cases = [
            {"target": "水", "recipe": "滷味", "others": "雞小腿, 豬後腿肉塊, 豆干, 鵪鶉蛋, 醬油, 辣椒, 滷味包, 冰糖, 米酒"},
            {"target": "滷味包", "recipe": "滷味", "others": "雞小腿, 豬後腿肉塊, 豆干, 鵪鶉蛋, 醬油, 辣椒, 水, 冰糖, 米酒"},
        ]
        
        for case in test_cases:
            print("\n" + "="*50)
            print(f"📌 目標: {case['target']} | 食譜: {case['recipe']}")
            
            match = tool.ask_llm_for_best_match(case['target'], case['recipe'], case['others'], verbose=True)
            
            if match:
                print(f"✨ 匹配名稱：{match.get('name')}")
                print(f"💡 挑選理由：{match.get('reason')}")
                print("-" * 30)
