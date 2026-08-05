import json
import os
import glob
import re
import difflib
from typing import List, Dict, Optional
from dotenv import load_dotenv

try:
    from openai import OpenAI
    from tenacity import retry, stop_after_attempt, wait_exponential
except ImportError:
    print("Error: Missing required packages: pip install openai tenacity python-dotenv")
    exit(1)

load_dotenv()

# ================= Configuration (與 3_3_match_ingredients.py 一致) =================
LLM_PROVIDER = "openai" 
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "your-openai-api-key")
OPENAI_MODEL = "gpt-4.1-nano"
OLLAMA_BASE_URL = "http://localhost:11434/v1"
OLLAMA_MODEL = "llama3.1:8b" 
# =================================================================================

def setup_client():
    if LLM_PROVIDER == "ollama":
        return OpenAI(api_key="ollama", base_url=OLLAMA_BASE_URL), OLLAMA_MODEL
    else:
        return OpenAI(api_key=OPENAI_API_KEY), OPENAI_MODEL

def clean_name(name: str) -> str:
    if not name: return ""
    return name.strip().replace('\n', '').replace('\r', '')

def get_shortest_name_info(candidates: List[Dict]) -> Optional[Dict[str, str]]:
    if not candidates: return None
    sorted_candidates = sorted(candidates, key=lambda x: len(x['樣品名稱']))
    best = sorted_candidates[0]
    return {"db_id": best['整合編號'], "db_name": best['樣品名稱']}

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10), reraise=True)
def call_llm(client, model, prompt):
    kwargs = {"model": model, "messages": [{"role": "user", "content": prompt}], "temperature": 0.0}
    if LLM_PROVIDER != "ollama": kwargs["response_format"] = {"type": "json_object"}
    response = client.chat.completions.create(**kwargs)
    return response.choices[0].message.content.strip()

def step1_get_category(client, model, target_ing: str, recipe_name: str, categories: List[str]) -> Optional[str]:
    cat_list_str = "、".join(categories)
    prompt = f"""
你是一個食材分類專家。請判斷以下食材最可能屬於哪一個「食品分類」。

【可選分類】：{cat_list_str}

【目標食材】：{target_ing}
【所屬食譜】：{recipe_name}

請回傳 JSON 格式：
{{
  "food_category": "挑選的分類名稱",
  "reason": "簡短理由"
}}
"""
    try:
        res = call_llm(client, model, prompt)
        data = json.loads(res[res.find('{'):res.rfind('}')+1])
        return data.get("food_category")
    except: return None

def step2_get_item(client, model, target_ing: str, recipe_name: str, context: str, category: str, item_list_str: str) -> Optional[Dict]:
    prompt = f"""
你是一個食材匹配專家。我們已確定食材「{target_ing}」屬於「{category}」分類。
請從以下清單中挑選出最精確的官方名稱。

【{category} 類別清單】：
{item_list_str}

【目標食材】：{target_ing}
【所屬食譜】：{recipe_name}
【其他上下文】：{context}

請遵循：
1. 必須從清單中挑選項目，盡量一字不漏。
2. 常識校正：如果是「XX包/粉」，優先找調味或香辛料性質的。

請回傳 JSON 格式：
{{
  "matched_name": "清單中的官方名稱",
  "reason": "挑選理由",
  "confidence": 0-100
}}
"""
    try:
        res = call_llm(client, model, prompt)
        return json.loads(res[res.find('{'):res.rfind('}')+1])
    except: return None

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    nutrition_dir = os.path.join(base_dir, '2_enrich_nutrition', 'output')
    nutrition_files = glob.glob(os.path.join(nutrition_dir, '2_nutrition_data_categorized_20260422_170816.json'))
    # print("nutrition_files :",nutrition_files)
    if not nutrition_files: return
    nutrition_file = max(nutrition_files, key=os.path.getmtime)
    print(f"載入營養資料庫：{os.path.basename(nutrition_file)}...")
    
    with open(nutrition_file, 'r', encoding='utf-8') as f: nutrition_data = json.load(f)

    name_to_items = {}
    category_to_names = {}
    for category, items in nutrition_data.items():
        cat_names = set()
        for item in items:
            formal = clean_name(item['樣品名稱'])
            aliases = [clean_name(a) for a in (item.get('俗名') or "").split(',') if clean_name(a)]
            for name in set([formal] + aliases):
                if name not in name_to_items: name_to_items[name] = []
                name_to_items[name].append(item)
                cat_names.add(name)
        category_to_names[category] = list(cat_names)

    categories_list = list(category_to_names.keys())
    client, model = setup_client()

    print("\n" + "="*50)
    print("🚀 3_3 專用測試工具 (兩階段匹配邏輯)")
    print(f"模式：{LLM_PROVIDER} ({model})")
    print("="*50)

    while True:
        target = input("\n請輸入食材名稱 (輸入 'q' 離開): ").strip()
        if target.lower() == 'q': break
        if not target: continue
        
        recipe = input("請輸入食譜名稱 (選填): ").strip() or "未指定食譜"
        context = input("請輸入其他上下文食材 (選填): ").strip() or "無"
        
        target_cleaned = clean_name(target)
        
        # 1. Exact Match
        if target_cleaned in name_to_items:
            info = get_shortest_name_info(name_to_items[target_cleaned])
            print(f"\n✅ [完全比對成功] 匹配：{info['db_name']} (ID: {info['db_id']})")
        else:
            # 2. Two-Step LLM Match
            print(f"\n🧠 [Step 1: 正在判定分類...]")
            cat = step1_get_category(client, model, target_cleaned, recipe, categories_list)
            
            # 類別自動校正
            if cat and cat not in category_to_names:
                matches = difflib.get_close_matches(cat, categories_list, n=1, cutoff=0.3)
                if matches:
                    print(f"🔧 [分類修正] '{cat}' -> '{matches[0]}'")
                    cat = matches[0]

            if cat:
                print(f"📂 [分類成功] 判定為：{cat}")
                print(f"🧠 [Step 2: 正在該分類中搜尋最佳匹配...]")
                item_list_str = "、".join(category_to_names[cat])
                llm_data = step2_get_item(client, model, target_cleaned, recipe, context, cat, item_list_str)
                
                if llm_data and llm_data.get("matched_name"):
                    matched_name = clean_name(llm_data["matched_name"])
                    
                    # 分類內校正
                    if matched_name not in name_to_items:
                        pool = category_to_names.get(cat, [])
                        correction = difflib.get_close_matches(matched_name, pool, n=1, cutoff=0.5)
                        if correction:
                            print(f"🔧 [自動校正] 將 '{matched_name}' 修正為 '{correction[0]}'")
                            matched_name = correction[0]

                    if matched_name in name_to_items:
                        info = get_shortest_name_info(name_to_items[matched_name])
                        print(f"✨ [匹配結果] 名稱：{info['db_name']} (ID: {info['db_id']}) | 信心：{llm_data.get('confidence')}%")
                        print(f"   理由：{llm_data.get('reason')}")
                    else:
                        print(f"❌ [失敗] 無法在該分類中找到確切匹配。")
                else:
                    print(f"❌ [失敗] LLM 未回傳有效名稱。")
            else:
                print(f"❌ [失敗] 無法判定分類。")

if __name__ == "__main__": main()
