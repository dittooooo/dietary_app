"""
修改內容摘要 (V3.2.1 - 階層式校正優化):
1. 階層式匹配 (Hierarchical Matching)：
   - Prompt 更新：將食材清單按「食品分類」分組餵給 LLM，強制其先判斷分類再找食材。
   - LLM 回傳 JSON 增加 "food_category" 欄位。
2. 分類內自動校正 (Category-Aware Auto-Correction)：
   - 當 LLM 回傳名稱不精準時，程式會優先在 LLM 指定的「食品分類」中尋找最接近的官方名稱。
   - 避免跨類別的字面誤判（例如：避免「紅酒」在全局搜尋中被誤校正為「紅豆」）。
3. 智慧快取與信心值機制保持。
"""

import json
import os
import re
import glob
import difflib
from typing import List, Dict, Optional
from dotenv import load_dotenv

try:
    from openai import OpenAI
    from tenacity import retry, stop_after_attempt, wait_exponential
    from tqdm import tqdm
except ImportError:
    print("Error: Missing required packages: pip install openai tenacity python-dotenv tqdm")
    exit(1)

load_dotenv()

# ================= Configuration =================
LLM_PROVIDER = "openai" 
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "your-openai-api-key")
OPENAI_MODEL = "gpt-4.1-nano"
OLLAMA_BASE_URL = "http://localhost:11434/v1"
OLLAMA_MODEL = "llama3.1:8b" # gemma4:e4b 

# LIMIT variable for testing. Set to None to process all unmatched ingredients.
LIMIT_LLM_CALLS = 50

# VERBOSE: Set to True to see detailed LLM matching logs, False to hide them.
VERBOSE_LLM_LOGS = True # True, False
# TQDM: Set to True to show progress bar, False to hide it.
SHOW_PROGRESS_BAR = False # True, False

# Smart Cache: Ingredients containing these words will use recipe-specific context.
AMBIGUOUS_KEYWORDS = ["油", "水", "奶", "粉", "糖", "醬", "湯", "奶油", "麵粉", "鹽"]
# =================================================

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

目前處理任務：
- 食譜名稱：{recipe_name}
- 其他上下文食材：{other_ingredients}
- 目標食材：{target_ingredient}

請遵循以下思考步驟：
1. 判斷「{target_ingredient}」最可能屬於哪一個「食品分類」。
2. 在該分類的清單中，找出最適合的官方名稱（例如：「紅酒」應對應「紅葡萄酒」）。
3. 若清單中有別名/俗名，也請納入考量，但回傳必須是清單內的字。
4. 常識校正：如果是「XX包/粉」，優先找「調味料/香辛料」類。

請回傳 JSON 格式（不要 Markdown）：
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
    recipes_file = os.path.join(base_dir, '1_organize_nutrition_by_category', 'input', 'recipes.json')
    nutrition_dir = os.path.join(base_dir, '2_enrich_nutrition', 'output')
    nutrition_files = glob.glob(os.path.join(nutrition_dir, '2_nutrition_enriched_*.json'))
    if not nutrition_files: return
    nutrition_file = max(nutrition_files, key=os.path.getmtime)
    
    with open(recipes_file, 'r', encoding='utf-8') as f: recipes = json.load(f)
    with open(nutrition_file, 'r', encoding='utf-8') as f: nutrition_data = json.load(f)

    # 1. 建立結構化資料庫與索引
    name_to_items = {}
    category_to_names = {} # 用於校正：{分類: [名稱清單]}
    all_known_names_list = []
    structured_parts = []

    for category, items in nutrition_data.items():
        cat_names = set()
        for item in items:
            formal_name = clean_name(item['樣品名稱'])
            aliases = [clean_name(a) for a in (item.get('俗名') or "").split(',') if clean_name(a)]
            for name in set([formal_name] + aliases):
                if name not in name_to_items:
                    name_to_items[name] = []
                    all_known_names_list.append(name)
                name_to_items[name].append(item)
                cat_names.add(name)
        category_to_names[category] = list(cat_names)
        structured_parts.append(f"[{category}]: {', '.join(list(cat_names))}")

    structured_names_str = "\n".join(structured_parts)
    client, model = setup_client()

    output_dir = os.path.join(base_dir, '3_match_ingredients', 'output')
    os.makedirs(output_dir, exist_ok=True)
    import datetime
    output_file = os.path.join(output_dir, f'3_2_recipes_matched_{datetime.datetime.now().strftime("%Y%m%d_%H%M%S")}.json')

    llm_cache = {}
    llm_call_count = 0
    stats = {"exact": 0, "llm_matched": 0, "unmatched": 0}

    print(f"\nStarting Hierarchical Matching (V3.2.1)...")
    recipe_loop = tqdm(recipes, desc="Processing Recipes") if SHOW_PROGRESS_BAR else recipes
    for recipe in recipe_loop:
        recipe_name = clean_name(recipe.get('name', 'Unknown'))
        ingredients = recipe.get('ingredients', [])
        ing_names = [clean_name(ing.get('name', '')) for ing in ingredients]
        other_ingredients_context = ", ".join([n for n in ing_names if n])
        
        for ing in ingredients:
            target_ing = clean_name(ing.get('name', ''))
            if not target_ing: continue
            
            if target_ing in name_to_items:
                info = get_shortest_name_info(name_to_items[target_ing])
                ing.update({"db_id": info['db_id'], "樣品名稱": info['db_name'], "match_method": "exact"})
                stats["exact"] += 1
                continue
            
            is_ambiguous = any(kw in target_ing for kw in AMBIGUOUS_KEYWORDS)
            cache_key = (recipe_name, target_ing) if is_ambiguous else target_ing
            
            if cache_key in llm_cache:
                llm_data = llm_cache[cache_key]
            else:
                if LIMIT_LLM_CALLS is not None and llm_call_count >= LIMIT_LLM_CALLS:
                    ing.update({"db_id": None, "樣品名稱": None}); stats["unmatched"] += 1; continue
                    
                if VERBOSE_LLM_LOGS:
                    context_info = f"Recipe: {recipe_name}" if is_ambiguous else "Global"
                    print("-" * 40)
                    print(f"  [LLM] Querying for: '{target_ing}' ({context_info})")
                llm_data = get_llm_match(client, model, target_ing, recipe_name, other_ingredients_context, structured_names_str)
                llm_cache[cache_key] = llm_data
                llm_call_count += 1
                
            if llm_data and llm_data.get("matched_name"):
                cat = llm_data.get("food_category")
                matched_name = clean_name(llm_data["matched_name"])
                
                # --- 分類感知校正 (Category-Aware Correction) ---
                if matched_name not in name_to_items:
                    search_pool = category_to_names.get(cat, all_known_names_list) if cat else all_known_names_list
                    correction = difflib.get_close_matches(matched_name, search_pool, n=1, cutoff=0.5)
                    if correction: matched_name = correction[0]

                if matched_name in name_to_items:
                    info = get_shortest_name_info(name_to_items[matched_name])
                    if VERBOSE_LLM_LOGS:
                        print(f"    -> LLM Matched: {info['db_name']} (Confidence: {llm_data.get('confidence')}%)")
                    ing.update({
                        "db_id": info['db_id'], "樣品名稱": info['db_name'], 
                        "llm_category": cat, "llm_confidence": llm_data.get("confidence"),
                        "match_method": "llm_hierarchical"
                    })
                    stats["llm_matched"] += 1
                else:
                    ing.update({"db_id": None, "樣品名稱": None}); stats["unmatched"] += 1
            else:
                ing.update({"db_id": None, "樣品名稱": None}); stats["unmatched"] += 1

    with open(output_file, 'w', encoding='utf-8') as f: json.dump(recipes, f, ensure_ascii=False, indent=2)
    print(f"\nSuccess! Results: {stats}")

if __name__ == "__main__": main()
