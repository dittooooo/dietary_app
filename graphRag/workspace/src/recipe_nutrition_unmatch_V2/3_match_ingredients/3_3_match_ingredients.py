"""
修改內容摘要 (V3.3 - 兩階段精準匹配):
1. 二段式匹配流程 (Two-Step Flow)：
   - 第一階段 (分類)：LLM 僅從 18 個大類別中選擇最適合的「食品分類」。
   - 第二階段 (挑選)：根據第一階段的分類，LLM 僅在該分類的 200~400 個食材中挑選精確名稱。
   - 優點：大幅減少 LLM 的資訊負荷（從 6000 降至 400），解決「紅酒配成紅茶」或「滷味包配成五味醬」的亂匹配問題。
2. 成本大幅優化：
   - 每次請求傳送的 Token 數從 ~50,000 降至 ~3,000，速度更快且更省錢。
3. 自動校正強化：
   - 第二階段後的校正被嚴格限制在第一階段選定的分類內，確保邏輯一致。
4. 介面與控制：
   - 保留 VERBOSE_LLM_LOGS 與 SHOW_PROGRESS_BAR 開關。
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
LLM_PROVIDER = "openai" # "ollama" or "openai"
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "your-openai-api-key")
OPENAI_MODEL = "gpt-4.1-nano"
OLLAMA_BASE_URL = "http://localhost:11434/v1"
OLLAMA_MODEL = "llama3.1:8b" 

LIMIT_LLM_CALLS = 50

# VERBOSE: Set to True to see detailed LLM matching logs, False to hide them.
VERBOSE_LLM_LOGS = True
# TQDM: Set to True to show progress bar, False to hide it.
SHOW_PROGRESS_BAR = True

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

def step1_get_category(client, model, target_ing: str, recipe_name: str, categories: List[str]) -> Optional[str]:
    """第一階段：判斷大類別"""
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
    """第二階段：在指定類別中精挑細選"""
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
    recipes_file = os.path.join(base_dir, '1_organize_nutrition_by_category', 'input', 'recipes.json')
    nutrition_dir = os.path.join(base_dir, '2_enrich_nutrition', 'output')
    nutrition_files = glob.glob(os.path.join(nutrition_dir, '2_nutrition_data_categorized_20260422_170816.json'))
    if not nutrition_files: return
    nutrition_file = max(nutrition_files, key=os.path.getmtime)
    
    with open(recipes_file, 'r', encoding='utf-8') as f: recipes = json.load(f)
    with open(nutrition_file, 'r', encoding='utf-8') as f: nutrition_data = json.load(f)

    # 1. 建立索引與分組
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

    output_dir = os.path.join(base_dir, '3_match_ingredients', 'output')
    os.makedirs(output_dir, exist_ok=True)
    import datetime
    output_file = os.path.join(output_dir, f'3_3_recipes_matched_{datetime.datetime.now().strftime("%Y%m%d_%H%M%S")}.json')

    llm_cache = {} # cache by cache_key
    llm_call_count = 0
    stats = {"exact": 0, "llm_matched": 0, "unmatched": 0}

    print(f"\nStarting Two-Step Matching (V3.3)...")
    recipe_loop = tqdm(recipes, desc="Processing Recipes") if SHOW_PROGRESS_BAR else recipes
    for recipe in recipe_loop:
        recipe_name = clean_name(recipe.get('name', 'Unknown'))
        ingredients = recipe.get('ingredients', [])
        context = ", ".join([clean_name(ing.get('name', '')) for ing in ingredients if ing.get('name')])
        
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
                    print("-" * 40)
                    print(f"  [LLM Step 1: Classifying] '{target_ing}'")
                
                # 第一階段：找類別
                cat = step1_get_category(client, model, target_ing, recipe_name, categories_list)
                
                # 類別校正 (防呆)
                if cat not in category_to_names:
                    cat = difflib.get_close_matches(cat, categories_list, n=1, cutoff=0.3)[0] if cat else None
                
                if cat:
                    if VERBOSE_LLM_LOGS: print(f"    -> Category: {cat}")
                    # 第二階段：找項目
                    item_list_str = "、".join(category_to_names[cat])
                    llm_data = step2_get_item(client, model, target_ing, recipe_name, context, cat, item_list_str)
                    if llm_data: llm_data["food_category"] = cat
                else:
                    llm_data = None
                
                llm_cache[cache_key] = llm_data
                llm_call_count += 1
                
            if llm_data and llm_data.get("matched_name"):
                cat = llm_data.get("food_category")
                matched_name = clean_name(llm_data["matched_name"])
                
                if matched_name not in name_to_items:
                    search_pool = category_to_names.get(cat, [])
                    correction = difflib.get_close_matches(matched_name, search_pool, n=1, cutoff=0.5)
                    if correction: matched_name = correction[0]

                if matched_name in name_to_items:
                    info = get_shortest_name_info(name_to_items[matched_name])
                    if VERBOSE_LLM_LOGS:
                        print(f"  [LLM Step 2: Matched] {info['db_name']} ({llm_data.get('confidence')}%)")
                    ing.update({
                        "db_id": info['db_id'], "樣品名稱": info['db_name'], 
                        "llm_category": cat, "llm_confidence": llm_data.get("confidence"),
                        "match_method": "llm_two_step"
                    })
                    stats["llm_matched"] += 1
                else:
                    ing.update({"db_id": None, "樣品名稱": None}); stats["unmatched"] += 1
            else:
                ing.update({"db_id": None, "樣品名稱": None}); stats["unmatched"] += 1

    with open(output_file, 'w', encoding='utf-8') as f: json.dump(recipes, f, ensure_ascii=False, indent=2)
    print(f"\nSuccess! Results: {stats}")

if __name__ == "__main__": main()
