"""
線上營養成分搜尋工具
此工具在本地 nutrition_data.json 找不到高信心度的食材時啟動。
依賴 OpenAI 的原生 web_search 工具抓取每 100g 的營養成分。
"""

import os
import json
import re
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

# Ensure we don't pass an empty base_url if it's default
if not BASE_URL or BASE_URL.strip() == "":
    client = OpenAI(api_key=API_KEY)
else:
    client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

# Ollama 的 OpenAI 相容 API 對 tools/web_search 與 `response_format` 支援不一；
# 用本機 Ollama 時先禁用 tools，避免 400: "does not support tools"。
USE_OLLAMA = isinstance(BASE_URL, str) and ("localhost:11434" in BASE_URL or "127.0.0.1:11434" in BASE_URL)


def _extract_json_object(text: str) -> dict:
    if text is None:
        raise ValueError("Empty LLM response (None)")
    raw = str(text).strip()
    if not raw:
        raise ValueError("Empty LLM response (blank)")
    raw = re.sub(r"^```(?:json)?\s*", "", raw, flags=re.IGNORECASE)
    raw = re.sub(r"\s*```$", "", raw)
    start = raw.find("{")
    end = raw.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError(f"LLM response is not JSON: {raw[:200]}")
    return json.loads(raw[start : end + 1])

class OnlineNutritionSearchTool:
    def __init__(self):
        pass

    def search_nutrition(self, ingredient_name, recipe_name="未知", verbose=False):
        """
        透過 OpenAI 內建的聯網功能，搜尋食材的 100g 營養數據
        """
        if verbose:
            print(f"🌐 [啟動聯網搜尋] 正在搜尋「{ingredient_name}」(食譜背景: {recipe_name}) 的營養成分...")
            
        system_prompt = f"""
你是一個嚴謹的營養學資料搜集助手。
你的任務是使用搜尋引擎，找出指定食材【每 100g】的標準營養成分。
如果它是帶有廠牌或特定種類的加工品（例如某種免煮麵皮、某種特定的糖），請盡量找該品項或最相似替代品的資料。
如果它是水、白開水等無熱量物質，請直接依靠常識填寫 0。

請務必以合法的 JSON 格式回傳，格式如下：
{{
  "name": "你最終採用的名稱 (加上簡短說明)",
  "熱量(kcal)": 數字 (float),
  "粗蛋白(g)": 數字 (float),
  "粗脂肪(g)": 數字 (float),
  "總碳水化合物(g)": 數字 (float),
  "鈉(mg)": 數字 (float)
}}

【注意事項】：
1. 數值請一律換算為「每 100g」的含量。
2. 只要產出上述格式的 JSON，不要加入其他對話內容或 Markdown 符號。
"""
        
        user_prompt = f"請查詢食材「{ingredient_name}」每 100g 的營養成分。該食材被用於食譜「{recipe_name}」中。"

        @retry(
            stop=stop_after_attempt(5),
            wait=wait_exponential(multiplier=1, min=5, max=120), # 聯網搜尋給予更長的等待
            retry=retry_if_exception_type(Exception),
            reraise=True
        )
        def _call_openai_search():
            kwargs = dict(
                model=MODEL_NAME,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                temperature=0.1,
            )
            if not USE_OLLAMA:
                kwargs["tools"] = [{"type": "web_search"}]
                kwargs["response_format"] = {"type": "json_object"}
            response = client.chat.completions.create(**kwargs)
            content = (response.choices[0].message.content or "").strip()
            return _extract_json_object(content)

        data = _call_openai_search()
        result_text = json.dumps(data, ensure_ascii=False)
        
        if verbose:
            print(f"🌐 [聯網搜尋成功] 取得結果: {result_text}")
            
        return data

if __name__ == "__main__":
    tool = OnlineNutritionSearchTool()
    
    test_items = [
        {"target": "免煮麵皮", "recipe": "義式千層麵"},
        {"target": "特級白開水", "recipe": "特製高湯"}
    ]
    
    for item in test_items:
        print(f"\n--- 測試搜尋: {item['target']} ---")
        result = tool.search_nutrition(item["target"], recipe_name=item["recipe"], verbose=True)
        print("回傳結果:", json.dumps(result, ensure_ascii=False, indent=2))
