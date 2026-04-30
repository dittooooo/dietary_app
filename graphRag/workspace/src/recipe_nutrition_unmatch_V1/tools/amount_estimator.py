"""
食材份量推估工具
給定食譜名稱、食材名稱與未標準化的份量（例如「12片」、「少許」、「1大匙」），
使用 LLM 推算出在該烹飪情境下合理的「公克數」(grams)。
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

if not BASE_URL or BASE_URL.strip() == "":
    client = OpenAI(api_key=API_KEY)
else:
    client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

# Ollama 的 OpenAI 相容 API 對 `response_format`/tools 支援不一，
# 部分模型（例如 gemma3:4b）會因為「工具」相關欄位而回 400。
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


class AmountEstimator:
    def __init__(self):
        pass

    def estimate_grams(self, recipe_name, ingredient_name, amount_raw, db_name=None, verbose=False):
        """
        推估食材公克數
        """
        if not amount_raw or amount_raw.strip() == "":
            return 0.0

        if verbose:
            db_info = f" (對應資料庫: {db_name})" if db_name else ""
            print(f"⚖️ [啟動推算] 正在推算食譜「{recipe_name}」中「{ingredient_name}」份量「{amount_raw}」{db_info}的真實公克數...")
            
        system_prompt = f"""
你是一個擁有豐富烹飪常識與營養學知識的專家。
你的任務是將食譜中不精確的「份量描述」（如 12片、一小把、少許、3片、2小匙）轉換為最接近真實的「公克數」(grams)。

請務必以合法的 JSON 格式回傳，格式如下：
{{
  "grams": 數字 (float),
  "reason": "你的推算邏輯簡述"
}}

【推算指引】：
1. 若份量已經明確標示克(g)或毫升(ml)或公克，請直接轉換（例如 "350克" -> 350.0，"200ml" 當作水大約是 200.0）。
2. 若是「少許」、「適量」，根據該食材在道菜中的常見用量給予合理推估（例如：鹽少許約 1~2g，白芝麻少許約 3~5g，水適量若為湯底可能是 500g）。
3. 杯、匙類：量米杯約 150g(米) 或 180g(水)；1大匙(TBSP)液體約15g，粉類約10g；1小匙(tsp)約5g。
4. 單位件數類：「12片免煮麵皮」若每片一般市售約 15~20g，則推估為 180~240g 之間；「1顆蛋」約 50g。
5. 盡你所能給出一個合理的均值，絕對不允許回傳 null，請一定要計算出一個 float 數字給 grams。
只要產出上述格式的 JSON，不要加入其他對話內容或 Markdown 符號。
"""
        db_hint = f"，（參考對應營養資料庫品項為：{db_name}）" if db_name else ""
        user_prompt = f"在這道食譜「{recipe_name}」中，食材「{ingredient_name}」的原始用量寫法為：「{amount_raw}」{db_hint}。請問這大約相當於多少公克？"

        @retry(
            stop=stop_after_attempt(5),
            wait=wait_exponential(multiplier=1, min=4, max=60),
            retry=retry_if_exception_type(Exception),
            reraise=True
        )
        def _call_openai_estimate():
            kwargs = dict(
                model=MODEL_NAME,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                temperature=0.1,
            )
            if not USE_OLLAMA:
                kwargs["response_format"] = {"type": "json_object"}
            response = client.chat.completions.create(**kwargs)
            content = (response.choices[0].message.content or "").strip()
            return _extract_json_object(content)

        data = _call_openai_estimate()
        result_text = json.dumps(data, ensure_ascii=False)
        
        if verbose:
            print(f"⚖️ [推算成功] 取得結果: {result_text}")
            
        return float(data.get("grams", 0.0))

if __name__ == "__main__":
    estimator = AmountEstimator()
    
    test_items = [
        {"recipe": "義式千層麵", "ingredient": "免煮麵皮", "amount": "12片"},
        {"recipe": "炒青菜", "ingredient": "鹽", "amount": "少許"},
        {"recipe": "紅燒肉", "ingredient": "水", "amount": "2杯(量米杯)"},
        {"recipe": "炒青菜", "ingredient": "黑胡椒", "amount": "1小匙"}
    ]
    
    for item in test_items:
        print(f"\n--- 測試推算: {item['ingredient']} ---")
        g = estimator.estimate_grams(item["recipe"], item["ingredient"], item["amount"], verbose=True)
        print("最終得出:", g, "grams")
