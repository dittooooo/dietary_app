"""
修改內容摘要 (V3.4 - 料理情境推斷優化):
1. 模糊食材情境推斷 (Contextual Inference)：
   - 針對「油、肉、菜、粉、糖」等模糊字眼，強制 LLM 根據「食譜名稱」與「食材組合」進行邏輯推斷。
   - 內建推斷規則：
     * 湯類/清蒸/日式 -> 傾向於「植物油/沙拉油/大豆油」。
     * 熱炒/紅燒 -> 傾向於「大豆油/豬油」。
     * 甜點/烘焙 -> 傾向於「無鹽奶油/橄欖油」。
2. 避免錯誤匹配：
   - 解決「油」被誤判為「人造奶油」的問題（因為人造奶油在字面上含有「油」字）。
   - 要求 LLM 在無法精確匹配時，挑選「該料理情境下最合理」的替代品。
3. 結構延續：
   - 保留 V3.3 的兩階段匹配 (分類 -> 挑選) 與 V3.2 的智慧快取/日誌。
"""

import json
import os
import re
import glob
import difflib
import time
from typing import List, Dict, Optional
from dotenv import load_dotenv

try:
    from openai import OpenAI
    from tenacity import retry, stop_after_attempt, wait_exponential
    from tqdm import tqdm
except ImportError:
    print("Error: Missing required packages: pip install openai tqdm python-dotenv")
    exit(1)

load_dotenv()

# ================= Configuration =================
LLM_PROVIDER = "openai" # "ollama" or "openai"
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "your-openai-api-key")
OPENAI_MODEL = "gpt-4.1-nano"
OLLAMA_BASE_URL = "http://localhost:11434/v1"
OLLAMA_MODEL = "llama3.1:8b" 

# 控制的是「API 呼叫次數」。決定你這次執行最多願意花費多少次 LLM 請求
LIMIT_LLM_CALLS = None # 設為 None 處理全部

# [測試範圍] 食譜處理起迄點 (0-indexed)
# 例如: START_INDEX = 0, END_INDEX = 10 會處理第 0 到第 9 本食譜
START_INDEX = 50
END_INDEX = 60


# VERBOSE: Set to True to see detailed LLM matching logs, False to hide them.
VERBOSE_LLM_LOGS = True
# TQDM: Set to True to show progress bar, False to hide it.
SHOW_PROGRESS_BAR = False

# Smart Cache: Ingredients containing these words will use recipe-specific context.
AMBIGUOUS_KEYWORDS = ["油", "水", "奶", "粉", "糖", "醬", "湯", "奶油", "麵粉", "鹽", "肉", "菜"]
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

def load_prompts(filename: str) -> str:
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "prompts", filename)
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8') as f:
            return f.read()
    return ""

def step1_get_category(client, model, target_ing: str, recipe_name: str, categories: List[str]) -> Optional[str]:
    cat_list_str = "、".join(categories)
    hints = load_prompts("category_hints.txt")
    prompt = f"""
你是一個食材分類專家。請判斷以下食材最可能屬於哪一個「食品分類」。

【可選分類】：{cat_list_str}

【目標食材】：{target_ing}
【所屬食譜】：{recipe_name}

{hints}

請回傳 JSON 格式（注意："food_category" 必須「完全等於」上述可選分類中的其中一項，絕對不可自行發明分類）：
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
你是一個專業的料理專家與營養資料庫專家。
目前任務是在「{category}」分類中，為食譜「{recipe_name}」中的食材「{target_ing}」找到最正確的資料庫名稱。

【{category} 類別清單】：
{item_list_str}

【情境資訊】：
- 目標食材：{target_ing}
- 食譜名稱：{recipe_name}
- 其他配料：{context}

### 💡 模糊食材推斷原則 (Inference Rules)：
若食材名稱很模糊（如：油、肉、菜），你必須根據料理情境推斷：
1. **湯類/清淡料理**：若食譜是鮮魚湯、味噌湯等，「油」通常指「大豆油、植物油、沙拉油」，不可選「人造奶油」或「香油」。
2. **中式熱炒**：若有蒜末、爆香，「油」多指「大豆油」或「豬油」。
3. **麵點/烘焙**：若食譜是蛋糕、麵包，「油」可能指「無鹽奶油」或「植物油」。
4. **排除法**：除非食譜明確要求，否則不要選擇帶有強烈特殊風味的油脂（如香油、奶油）。

請從清單中選出一個最合理的官方名稱。
回傳 JSON 格式（注意："matched_name" 必須「完全等於」上述【類別清單】中的某一個項目，絕對不可自行創造縮寫或清單上沒有的名稱）：
{{
  "matched_name": "清單中的官方名稱",
  "reason": "考慮食譜情境後的推斷理由",
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
    
    # 優先使用最新精細化分類的資料庫
    refined_files = glob.glob(os.path.join(base_dir, '1_organize_nutrition_by_category', 'input', '1_nutrition_data_categorized_refined.json'))
    if refined_files:
        nutrition_file = refined_files[0]
    else:
        nutrition_files = glob.glob(os.path.join(nutrition_dir, '2_nutrition_data_categorized_20260422_170816.json'))
        if not nutrition_files: print("找不到資料庫"); return
        nutrition_file = max(nutrition_files, key=os.path.getmtime)
    
    print(f"Using Database: {os.path.basename(nutrition_file)}")
    with open(recipes_file, 'r', encoding='utf-8') as f: recipes = json.load(f)
    
    # 根據設定切分食譜處理範圍
    if START_INDEX is not None or END_INDEX is not None:
        start = START_INDEX if START_INDEX is not None else 0
        end = END_INDEX if END_INDEX is not None else len(recipes)
        print(f"Processing Recipe Range: {start} to {end} (Total available: {len(recipes)})")
        recipes = recipes[start:end]

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

    output_dir = os.path.join(base_dir, '3_match_ingredients', 'output')
    os.makedirs(output_dir, exist_ok=True)
    import datetime
    output_file = os.path.join(output_dir, f'3_4_recipes_matched_{datetime.datetime.now().strftime("%Y%m%d_%H%M%S")}.json')

    llm_cache = {}
    llm_call_count = 0
    stats = {"exact": 0, "llm_matched": 0, "fallback_matched": 0, "unmatched": 0}

    print(f"\nStarting Context-Aware Matching (V3.4)...")
    recipe_loop = tqdm(recipes, desc="Processing Recipes") if SHOW_PROGRESS_BAR else recipes
    for recipe in recipe_loop:
        recipe_name = clean_name(recipe.get('name', 'Unknown'))
        ingredients = recipe.get('ingredients', [])
        context_str = ", ".join([clean_name(ing.get('name', '')) for ing in ingredients if ing.get('name')])
        
        for ing in ingredients:
            target_ing = clean_name(ing.get('name', ''))
            if not target_ing: continue
            
            # 只有非常明確的精確匹配才跳過 LLM
            if target_ing in name_to_items and target_ing not in AMBIGUOUS_KEYWORDS:
                info = get_shortest_name_info(name_to_items[target_ing])
                ing.update({"db_id": info['db_id'], "樣品名稱": info['db_name'], "match_method": "exact"})
                stats["exact"] += 1
                continue
            
            # 針對模糊關鍵字，強制快取時考慮食譜名稱
            is_ambiguous = any(kw in target_ing for kw in AMBIGUOUS_KEYWORDS)
            cache_key = (recipe_name, target_ing) if is_ambiguous else target_ing
            
            if cache_key in llm_cache:
                llm_data = llm_cache[cache_key]
            else:
                if LIMIT_LLM_CALLS is not None and llm_call_count >= LIMIT_LLM_CALLS:
                    ing.update({"db_id": None, "樣品名稱": None}); stats["unmatched"] += 1; continue
                
                if VERBOSE_LLM_LOGS:
                    print("-" * 40)
                    print(f"  [LLM] Inferring: '{target_ing}' in Recipe '{recipe_name}'")
                
                cat = step1_get_category(client, model, target_ing, recipe_name, categories_list)
                if cat and cat not in category_to_names:
                    matches = difflib.get_close_matches(cat, categories_list, n=1, cutoff=0.6)
                    cat = matches[0] if matches else None
                
                if cat:
                    item_list_str = "、".join(category_to_names[cat])
                    llm_data = step2_get_item(client, model, target_ing, recipe_name, context_str, cat, item_list_str)
                    if llm_data: llm_data["food_category"] = cat
                else:
                    llm_data = None
                
                llm_cache[cache_key] = llm_data
                llm_call_count += 1
                
            if llm_data and llm_data.get("matched_name"):
                cat = llm_data.get("food_category")
                matched_name = clean_name(llm_data["matched_name"])
                
                # 分類內自動校正
                if matched_name not in name_to_items:
                    search_pool = category_to_names.get(cat, [])
                    correction = difflib.get_close_matches(matched_name, search_pool, n=1, cutoff=0.6)
                    if correction: matched_name = correction[0]

                # 檢查匹配結果
                if matched_name in name_to_items:
                    info = get_shortest_name_info(name_to_items[matched_name])
                    if VERBOSE_LLM_LOGS:
                        print(f"    -> Inferred Match: {info['db_name']} ({llm_data.get('confidence')}%)")
                        print(f"       Reason: {llm_data.get('reason')}")
                    ing.update({
                        "db_id": info['db_id'], "樣品名稱": info['db_name'], 
                        "llm_category": cat, "llm_confidence": llm_data.get("confidence"),
                        "match_method": "llm_context_inference"
                    })
                    stats["llm_matched"] += 1
                else:
                    # [全域救援機制]
                    global_pool = list(name_to_items.keys())
                    global_correction = difflib.get_close_matches(target_ing, global_pool, n=1, cutoff=0.6)
                    if global_correction:
                        matched_name = global_correction[0]
                        info = get_shortest_name_info(name_to_items[matched_name])
                        if VERBOSE_LLM_LOGS:
                            print(f"    🆘 Fallback Match: {info['db_name']} (Found globally)")
                        ing.update({
                            "db_id": info['db_id'], "樣品名稱": info['db_name'], 
                            "match_method": "global_fuzzy_fallback"
                        })
                        stats["fallback_matched"] += 1
                    else:
                        ing.update({"db_id": None, "樣品名稱": None})
                        stats["unmatched"] += 1
            else:
                # 若 LLM 完全未回傳，也嘗試全域救援
                global_pool = list(name_to_items.keys())
                global_correction = difflib.get_close_matches(target_ing, global_pool, n=1, cutoff=0.6)
                if global_correction:
                    matched_name = global_correction[0]
                    info = get_shortest_name_info(name_to_items[matched_name])
                    if VERBOSE_LLM_LOGS:
                        print(f"    🆘 Fallback Match: {info['db_name']} (Found globally)")
                    ing.update({
                        "db_id": info['db_id'], "樣品名稱": info['db_name'], 
                        "match_method": "global_fuzzy_fallback"
                    })
                    stats["fallback_matched"] += 1
                else:
                    ing.update({"db_id": None, "樣品名稱": None})
                    stats["unmatched"] += 1

    with open(output_file, 'w', encoding='utf-8') as f: json.dump(recipes, f, ensure_ascii=False, indent=2)
    print(f"\nSuccess! Results: {stats}")

if __name__ == "__main__": main()
