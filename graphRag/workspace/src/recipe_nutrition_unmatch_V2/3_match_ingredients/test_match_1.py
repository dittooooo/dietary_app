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

# ================= Configuration (與 3_2_match_ingredients.py 一致) =================
LLM_PROVIDER = "openai" 
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "your-openai-api-key")
OPENAI_MODEL = "gpt-4.1-nano"
OLLAMA_BASE_URL = "http://localhost:11434/v1"
OLLAMA_MODEL = "gemma4:e4b" 
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

def get_llm_match(client, model, target_ingredient: str, recipe_name: str, other_ingredients: str, structured_names_str: str) -> Optional[Dict]:
    prompt = f"""
你是一個專業的台灣食材與營養資料庫專家。

以下是台灣食品營養資料庫中的所有食材，已按「食品分類」分組：
【資料庫清單開始】
{structured_names_str}
【資料庫清單結束】

目前測試任務：
- 食譜名稱：{recipe_name}
- 其他上下文食材：{other_ingredients}
- 目標食材：{target_ingredient}

請遵循以下思考步驟：
1. 判斷「{target_ingredient}」最可能屬於哪一個「食品分類」。
2. 在該分類的清單中，找出最適合的官方名稱（例如：「紅酒」應對應「紅葡萄酒」）。
3. 常識校正：如果是「XX包/粉」，優先找「調味料/香辛料」類。

請回傳 JSON 格式：
{{
  "food_category": "你判斷的分類名稱",
  "matched_name": "清單中的官方名稱",
  "reason": "挑選理由",
  "confidence": 0-100
}}
"""
    try:
        result_text = call_llm(client, model, prompt)
        start_idx = result_text.find('{')
        end_idx = result_text.rfind('}')
        if start_idx != -1 and end_idx != -1:
            return json.loads(result_text[start_idx:end_idx+1])
        return None
    except Exception as e:
        print(f"  [LLM Error] {e}")
        return None

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    nutrition_dir = os.path.join(base_dir, '2_enrich_nutrition', 'output')
    nutrition_files = glob.glob(os.path.join(nutrition_dir, '2_nutrition_enriched_*.json'))
    if not nutrition_files: return
    nutrition_file = max(nutrition_files, key=os.path.getmtime)
    print(f"載入營養資料庫：{os.path.basename(nutrition_file)}...")
    
    with open(nutrition_file, 'r', encoding='utf-8') as f: nutrition_data = json.load(f)

    name_to_items = {}
    category_to_names = {}
    all_known_names_list = []
    structured_parts = []

    for category, items in nutrition_data.items():
        cat_names = set()
        for item in items:
            formal_name = clean_name(item['樣品名稱'])
            aliases = [clean_name(a) for a in (item.get('俗名') or "").split(',') if clean_name(a)]
            for name in set([formal_name] + aliases):
                if name not in name_to_items:
                    name_to_items[name] = []; all_known_names_list.append(name)
                name_to_items[name].append(item)
                cat_names.add(name)
        category_to_names[category] = list(cat_names)
        structured_parts.append(f"[{category}]: {', '.join(list(cat_names))}")

    structured_names_str = "\n".join(structured_parts)
    client, model = setup_client()

    print("\n" + "="*50)
    print("🚀 單獨食材匹配測試工具 (V3.2.1 階層式)")
    print(f"模式：{LLM_PROVIDER} ({model})")
    print("="*50)

    while True:
        target = input("\n請輸入食材名稱 (輸入 'q' 離開): ").strip()
        if target.lower() == 'q': break
        if not target: continue
        
        recipe = input("請輸入食譜名稱 (選填): ").strip() or "未指定食譜"
        context = input("請輸入其他上下文食材 (選填): ").strip() or "無"
        
        target_cleaned = clean_name(target)
        
        if target_cleaned in name_to_items:
            info = get_shortest_name_info(name_to_items[target_cleaned])
            print(f"\n✅ [完全比對成功] 匹配：{info['db_name']} (ID: {info['db_id']})")
        else:
            print(f"\n🧠 [階層式智慧匹配中...]")
            llm_data = get_llm_match(client, model, target_cleaned, recipe, context, structured_names_str)
            
            if llm_data and llm_data.get("matched_name"):
                cat = llm_data.get("food_category")
                matched_name = clean_name(llm_data["matched_name"])
                
                # --- 分類感知校正 ---
                if matched_name not in name_to_items:
                    search_pool = category_to_names.get(cat, all_known_names_list) if cat else all_known_names_list
                    correction = difflib.get_close_matches(matched_name, search_pool, n=1, cutoff=0.5)
                    if correction:
                        print(f"🔧 [分類內校正] 在 '{cat}' 分類中將 '{matched_name}' 修正為 '{correction[0]}'")
                        matched_name = correction[0]
                
                if matched_name in name_to_items:
                    info = get_shortest_name_info(name_to_items[matched_name])
                    print(f"✨ [匹配結果] 分類：{cat} | 名稱：{info['db_name']} | 信心：{llm_data.get('confidence')}%")
                    print(f"   理由：{llm_data.get('reason')}")
                else:
                    print(f"❌ [失敗] 無法在分類 '{cat}' 中找到匹配項目。")
            else:
                print(f"❌ [LLM 無法找到合適匹配]")

if __name__ == "__main__": main()
