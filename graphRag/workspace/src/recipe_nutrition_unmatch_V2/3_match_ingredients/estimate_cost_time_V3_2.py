import json
import os
import glob

def clean_name(name: str) -> str:
    if not name: return ""
    return name.strip().replace('\n', '').replace('\r', '')

def estimate_tokens(text: str) -> int:
    # 繁體中文與結構化符號估算：1 字元約 1.5 tokens
    return int(len(text) * 1.5)

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    recipes_file = os.path.join(base_dir, '1_organize_nutrition_by_category', 'input', 'recipes.json')
    nutrition_dir = os.path.join(base_dir, '2_enrich_nutrition', 'output')
    nutrition_files = glob.glob(os.path.join(nutrition_dir, '2_nutrition_enriched_*.json'))
    
    if not nutrition_files:
        print("找不到營養資料庫檔案")
        return
        
    nutrition_file = max(nutrition_files, key=os.path.getmtime)
    
    with open(recipes_file, 'r', encoding='utf-8') as f: recipes = json.load(f)
    with open(nutrition_file, 'r', encoding='utf-8') as f: nutrition_data = json.load(f)

    # 1. 模擬 V3.2.1 的階層式資料結構
    name_to_items = {}
    structured_parts = []
    AMBIGUOUS_KEYWORDS = ["油", "水", "奶", "粉", "糖", "醬", "湯", "奶油", "麵粉", "鹽"]

    for category, items in nutrition_data.items():
        cat_names = set()
        for item in items:
            formal_name = clean_name(item['樣品名稱'])
            aliases = [clean_name(a) for a in (item.get('俗名') or "").split(',') if clean_name(a)]
            for name in set([formal_name] + aliases):
                name_to_items[name] = True
                cat_names.add(name)
        structured_parts.append(f"[{category}]: {', '.join(list(cat_names))}")

    structured_names_str = "\n".join(structured_parts)
    
    # 2. 計算基底 Prompt Token 數 (包含結構化清單)
    # V3.2 的 Prompt 比 V3.1 長，因為多了思考步驟說明
    base_prompt_tokens = estimate_tokens(structured_names_str) + 400 

    unique_llm_queries = {}
    exact_matches = 0

    # 3. 模擬智慧快取流程
    for recipe in recipes:
        recipe_name = clean_name(recipe.get('name', 'Unknown'))
        ingredients = recipe.get('ingredients', [])
        ing_names = [clean_name(ing.get('name', '')) for ing in ingredients]
        context = ", ".join([n for n in ing_names if n])
        
        for ing in ingredients:
            target_ing = clean_name(ing.get('name', ''))
            if not target_ing: continue
            
            if target_ing in name_to_items:
                exact_matches += 1
            else:
                # 智慧快取判斷
                is_ambiguous = any(kw in target_ing for kw in AMBIGUOUS_KEYWORDS)
                cache_key = (recipe_name, target_ing) if is_ambiguous else target_ing
                
                if cache_key not in unique_llm_queries:
                    unique_llm_queries[cache_key] = (recipe_name, target_ing, context)

    total_llm_calls = len(unique_llm_queries)
    
    # 4. 計算總 Tokens
    total_input_tokens = 0
    # V3.2 回傳 JSON 包含 category, matched_name, reason, confidence，約 50~100 tokens
    total_output_tokens = total_llm_calls * 80 

    for req in unique_llm_queries.values():
        r_name, t_ing, ctx = req
        dynamic_tokens = estimate_tokens(r_name + ctx + t_ing)
        total_input_tokens += (base_prompt_tokens + dynamic_tokens)

    # 5. 費用估算 (以您的設定 $0.1 / $0.4 每百萬 Token 計)
    PRICE_PER_1M_INPUT = 0.1
    PRICE_PER_1M_OUTPUT = 0.4
    
    total_cost_usd = (total_input_tokens / 1_000_000) * PRICE_PER_1M_INPUT + (total_output_tokens / 1_000_000) * PRICE_PER_1M_OUTPUT
    
    TIME_OLLAMA_PER_CALL_SEC = 3.0 # V3.2 思考較久，抓 3 秒
    TIME_OPENAI_PER_CALL_SEC = 1.0

    print("=" * 60)
    print("📊 3_2_match_ingredients.py (階層式智慧匹配) 執行預估")
    print("=" * 60)
    print(f"🔹 總計食材數量 : {exact_matches + total_llm_calls} (含重複)")
    print(f"🔹 直接匹配成功 : {exact_matches}")
    print(f"🔹 需呼叫 LLM 次數 : {total_llm_calls} (智慧快取後)")
    print("-" * 60)
    print(f"📝 預估總 Input Tokens  : {total_input_tokens:,}")
    print(f"📝 預估總 Output Tokens : {total_output_tokens:,}")
    print(f"💰 預估 API 費用 (OpenAI): ${total_cost_usd:.4f} USD")
    print("-" * 60)
    print(f"⏳ 預估時間 (Ollama)  : {total_llm_calls * TIME_OLLAMA_PER_CALL_SEC / 60:.2f} 分鐘")
    print(f"⏳ 預估時間 (OpenAI)  : {total_llm_calls * TIME_OPENAI_PER_CALL_SEC / 60:.2f} 分鐘")
    print("=" * 60)

if __name__ == "__main__":
    main()
