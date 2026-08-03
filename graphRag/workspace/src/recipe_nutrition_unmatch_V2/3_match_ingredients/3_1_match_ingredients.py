import json
import os
import re
import glob
from typing import List, Dict, Optional
from dotenv import load_dotenv

# Try importing openai, handle gracefully if missing
try:
    from openai import OpenAI
    from tenacity import retry, stop_after_attempt, wait_exponential
    from tqdm import tqdm
except ImportError:
    print("Error: Missing required packages. Please install them using:")
    print("pip install openai tenacity python-dotenv tqdm")
    exit(1)

load_dotenv()

# ================= Configuration =================
LLM_PROVIDER = "ollama"  # Options: "openai" or "ollama"
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "your-openai-api-key")
OPENAI_MODEL = "gpt-4.1-nano"
OLLAMA_BASE_URL = "http://localhost:11434/v1"
OLLAMA_MODEL = "gemma4:e4b" # User preferred model from conversation

# LIMIT variable for testing. Set to None to process all unmatched ingredients.
LIMIT_LLM_CALLS = 50

# Smart Cache: Ingredients containing these words will use recipe-specific context.
# Others will use global cache to save costs.
AMBIGUOUS_KEYWORDS = ["油", "水", "奶", "粉", "糖", "醬", "湯", "奶油", "麵粉"]
# =================================================

def setup_client():
    if LLM_PROVIDER == "ollama":
        return OpenAI(api_key="ollama", base_url=OLLAMA_BASE_URL), OLLAMA_MODEL
    else:
        return OpenAI(api_key=OPENAI_API_KEY), OPENAI_MODEL

def clean_name(name: str) -> str:
    if not name:
        return ""
    # Basic cleaning: strip whitespace, remove newlines
    return name.strip().replace('\n', '').replace('\r', '')

def get_shortest_name_info(candidates: List[Dict]) -> Optional[Dict[str, str]]:
    """Heuristic: Choose the candidate with the shortest formal name (most generic)."""
    if not candidates:
        return None
    sorted_candidates = sorted(candidates, key=lambda x: len(x['樣品名稱']))
    best = sorted_candidates[0]
    return {
        "db_id": best['整合編號'],
        "db_name": best['樣品名稱']
    }

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    reraise=True
)
def call_llm(client, model, prompt):
    kwargs = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.0,
    }
    if LLM_PROVIDER != "ollama":
        kwargs["response_format"] = {"type": "json_object"}
    
    response = client.chat.completions.create(**kwargs)
    return response.choices[0].message.content.strip()

def get_llm_match(client, model, target_ingredient: str, recipe_name: str, other_ingredients: str, available_names_str: str) -> Optional[str]:
    prompt = f"""
你是一個專業的營養學與資料庫檢索助手。

以下是台灣食品營養資料庫中所有的合法食材名稱：
【資料庫清單開始】
{available_names_str}
【資料庫清單結束】

現在我們正在處理食譜的食材標準化：
- 食譜名稱：{recipe_name}
- 其他食材：{other_ingredients}

請為以下「目標食材」從上述清單中找出最適合的「唯一對應項目」：
【目標食材】：{target_ingredient}

【重要挑選準則】：
1. 找出一個最適合在該食譜中作為替代的項目（如：目標為「披薩起士絲」，應選擇「起司」或「刨絲乾酪」）。
2. 你回傳的 matched_name 必須「一字不漏」地來自於上面的資料庫清單。
3. 如果真的完全沒有任何可替代的合理食材，回傳 null。

請一律以合法的 JSON 格式回傳，不要有任何其他 markdown 或是對話文字：
{{
  "matched_name": "你挑選的官方名稱"
}}
"""
    try:
        result_text = call_llm(client, model, prompt)
        
        # Try to parse JSON robustly
        start_idx = result_text.find('{')
        end_idx = result_text.rfind('}')
        if start_idx != -1 and end_idx != -1:
            json_str = result_text[start_idx:end_idx+1]
            data = json.loads(json_str)
            matched = data.get("matched_name")
            return clean_name(matched) if matched else None
        return None
    except Exception as e:
        print(f"  [LLM Error] {e}")
        return None

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    # Locate V2 input recipes
    recipes_file = os.path.join(base_dir, '1_organize_nutrition_by_category', 'input', 'recipes.json')
    if not os.path.exists(recipes_file):
        print(f"Error: Input recipes missing at {recipes_file}")
        return

    # Locate the latest enriched nutrition database
    nutrition_dir = os.path.join(base_dir, '2_enrich_nutrition', 'output')
    nutrition_files = glob.glob(os.path.join(nutrition_dir, '2_nutrition_enriched_*.json'))
    if not nutrition_files:
        print(f"Error: Enriched nutrition data not found in {nutrition_dir}")
        return
    
    # Get the most recently modified enriched data file
    nutrition_file = max(nutrition_files, key=os.path.getmtime)
    
    output_dir = os.path.join(base_dir, '3_match_ingredients', 'output')
    os.makedirs(output_dir, exist_ok=True)
    
    # Append datetime to output filename for tracking
    import datetime
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = os.path.join(output_dir, f'3_recipes_matched_{timestamp}.json')

    print(f"Loading recipes from {recipes_file}...")
    with open(recipes_file, 'r', encoding='utf-8') as f:
        recipes = json.load(f)

    print(f"Loading nutrition data from {os.path.basename(nutrition_file)}...")
    with open(nutrition_file, 'r', encoding='utf-8') as f:
        nutrition_data = json.load(f)

    # 1. Build lookup maps with cleaned names
    name_to_items = {}
    all_known_names = set()

    for category in nutrition_data:
        for item in nutrition_data[category]:
            formal_name = clean_name(item['樣品名稱'])
            aliases = [clean_name(a) for a in (item.get('俗名') or "").split(',') if clean_name(a)]
            
            all_names = set([formal_name] + aliases)
            for name in all_names:
                if name not in name_to_items:
                    name_to_items[name] = []
                    all_known_names.add(name)
                name_to_items[name].append(item)

    available_names_str = "、".join(list(all_known_names))
    print(f"Indexed {len(all_known_names)} unique names from nutrition database.")

    # 2. Process matching
    llm_cache = {} # cache by (recipe_name, target_ingredient) to save calls
    llm_call_count = 0
    stats = {"exact": 0, "llm_matched": 0, "unmatched": 0}

    client, model = setup_client()

    print("\nStarting matching process...")
    for i, recipe in enumerate(tqdm(recipes, desc="Processing Recipes")):
        recipe_name = clean_name(recipe.get('name', 'Unknown'))
        ingredients = recipe.get('ingredients', [])
        
        # Get a string of other ingredients for context
        ing_names = [clean_name(ing.get('name', '')) for ing in ingredients]
        other_ingredients_context = ", ".join([n for n in ing_names if n])
        
        for ing in ingredients:
            target_ing = clean_name(ing.get('name', ''))
            if not target_ing:
                ing['db_id'] = None
                ing['樣品名稱'] = None
                continue
            
            # Phase A: Exact Match
            if target_ing in name_to_items:
                info = get_shortest_name_info(name_to_items[target_ing])
                ing['db_id'] = info['db_id']
                ing['樣品名稱'] = info['db_name']
                stats["exact"] += 1
                continue
            
            # Phase B: LLM Match (Only if limit not reached)
            # Smart Cache Decision:
            is_ambiguous = any(kw in target_ing for kw in AMBIGUOUS_KEYWORDS)
            cache_key = (recipe_name, target_ing) if is_ambiguous else target_ing
            
            if cache_key in llm_cache:
                llm_response = llm_cache[cache_key]
            else:
                if LIMIT_LLM_CALLS is not None and llm_call_count >= LIMIT_LLM_CALLS:
                    ing['db_id'] = None
                    ing['樣品名稱'] = None
                    stats["unmatched"] += 1
                    continue
                    
                context_info = f"Recipe: {recipe_name}" if is_ambiguous else "Global"
                print(f"  [LLM] Querying for: '{target_ing}' ({context_info})")
                llm_response = get_llm_match(client, model, target_ing, recipe_name, other_ingredients_context, available_names_str)
                llm_cache[cache_key] = llm_response
                llm_call_count += 1
                
            if llm_response and llm_response in name_to_items:
                info = get_shortest_name_info(name_to_items[llm_response])
                ing['db_id'] = info['db_id']
                ing['樣品名稱'] = info['db_name']
                stats["llm_matched"] += 1
                print(f"    -> LLM Matched: {info['db_name']}")
            else:
                ing['db_id'] = None
                ing['樣品名稱'] = None
                stats["unmatched"] += 1
                if llm_response:
                    print(f"    -> LLM returned invalid or unrecognized name: {llm_response}")
                else:
                    print(f"    -> LLM could not find a match.")

    # 3. Save results
    print(f"\nSaving results to {output_file}...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(recipes, f, ensure_ascii=False, indent=2)

    print("\nMatching Summary:")
    print(f" - Exact Matches: {stats['exact']}")
    print(f" - LLM Matches: {stats['llm_matched']}")
    print(f" - Unmatched: {stats['unmatched']} (Limit was: {LIMIT_LLM_CALLS})")
    print(f"Success! Output at {output_file}")

if __name__ == "__main__":
    main()
