import json
import os
import glob

def clean_name(name: str) -> str:
    if not name:
        return ""
    return name.strip().replace('\n', '').replace('\r', '')

def estimate_tokens(text: str) -> int:
    """
    粗略估算 Token 數量。
    對於繁體中文，OpenAI 的 tokenizer 通常 1 個中文字約佔 1~2 個 tokens。
    這裡採用較保守的估計： 1 個字元 = 1.5 tokens。
    """
    return int(len(text) * 1.5)

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    recipes_file = os.path.join(base_dir, '1_organize_nutrition_by_category', 'input', 'recipes.json')
    nutrition_dir = os.path.join(base_dir, '2_enrich_nutrition', 'output')
    nutrition_files = glob.glob(os.path.join(nutrition_dir, '2_nutrition_enriched_*.json'))
    
    if not nutrition_files:
        print("找不到營養資料庫檔案")
        return
        
    AMBIGUOUS_KEYWORDS = ["油", "水", "奶", "粉", "糖", "醬", "湯", "奶油", "麵粉"]
    nutrition_file = max(nutrition_files, key=os.path.getmtime)

    with open(recipes_file, 'r', encoding='utf-8') as f:
        recipes = json.load(f)

    with open(nutrition_file, 'r', encoding='utf-8') as f:
        nutrition_data = json.load(f)

    # 建立目前資料庫的快取清單以模擬 Exact Match
    name_to_items = {}
    all_known_names = set()

    for category in nutrition_data:
        for item in nutrition_data[category]:
            formal_name = clean_name(item['樣品名稱'])
            aliases = [clean_name(a) for a in (item.get('俗名') or "").split(',') if clean_name(a)]
            all_names = set([formal_name] + aliases)
            for name in all_names:
                name_to_items[name] = True
                all_known_names.add(name)

    available_names_str = "、".join(list(all_known_names))
    
    # 計算基底 Prompt Token 數 (系統提示詞 + 6000多個食材清單)
    base_prompt_tokens = estimate_tokens(available_names_str) + 200 

    unique_llm_queries = {}
    exact_matches = 0

    # 模擬主程式的迴圈流程
    for recipe in recipes:
        recipe_name = clean_name(recipe.get('name', 'Unknown'))
        ingredients = recipe.get('ingredients', [])
        
        # 收集上下文
        ing_names = [clean_name(ing.get('name', '')) for ing in ingredients]
        other_ingredients_context = ", ".join([n for n in ing_names if n])
        
        for ing in ingredients:
            target_ing = clean_name(ing.get('name', ''))
            if not target_ing:
                continue
            
            # 完全比對 (不消耗 LLM)
            if target_ing in name_to_items:
                exact_matches += 1
            else:
                # 智慧快取 (Smart Cache)
                is_ambiguous = any(kw in target_ing for kw in AMBIGUOUS_KEYWORDS)
                cache_key = (recipe_name, target_ing) if is_ambiguous else target_ing
                
                if cache_key not in unique_llm_queries:
                    unique_llm_queries[cache_key] = (recipe_name, target_ing, other_ingredients_context)

    total_llm_calls = len(unique_llm_queries)
    
    # 計算總 Tokens
    total_input_tokens = 0
    total_output_tokens = total_llm_calls * 15 # JSON 輸出約 10~20 tokens，抓平均 15

    for req in unique_llm_queries.values():
        recipe_name, target_ing, context = req
        dynamic_text = recipe_name + context + target_ing
        dynamic_tokens = estimate_tokens(dynamic_text)
        total_input_tokens += (base_prompt_tokens + dynamic_tokens)

    # ================= 費用與時間預估設定 =================
    # gpt-4.1-nano 是較新的模型，這邊以 gpt-4o-mini 或相近的小模型定價作範例參考
    # (預設假設：Input $0.150 / 1M, Output $0.600 / 1M)
    PRICE_PER_1M_INPUT = 0.1
    PRICE_PER_1M_OUTPUT = 0.4
    
    total_cost_usd = (total_input_tokens / 1_000_000) * PRICE_PER_1M_INPUT + (total_output_tokens / 1_000_000) * PRICE_PER_1M_OUTPUT
    
    # 預估每筆呼叫的延遲時間
    TIME_OLLAMA_PER_CALL_SEC = 2.5 # 本地端模型約 2~4 秒
    TIME_OPENAI_PER_CALL_SEC = 0.8 # OpenAI API 約 0.5~1 秒
    
    AMBIGUOUS_KEYWORDS = ["油", "水", "奶", "粉", "糖", "醬", "湯", "奶油", "麵粉"]

    time_ollama_seconds = total_llm_calls * TIME_OLLAMA_PER_CALL_SEC
    time_openai_seconds = total_llm_calls * TIME_OPENAI_PER_CALL_SEC
    # ====================================================

    print("=" * 55)
    print("📊 3_match_ingredients.py 執行成本與時間預估報告")
    print("=" * 55)
    print(f"🔹 總計需要處理的食材數量 : {exact_matches + total_llm_calls} (含重複)")
    print(f"🔹 直接完全比對成功 (免LLM) : {exact_matches}")
    print(f"🔹 實際需要呼叫 LLM 的次數 : {total_llm_calls} (已扣除快取重複)")
    print("-" * 55)
    print(f"📝 單次呼叫的平均 Input Tokens : {int(total_input_tokens/total_llm_calls if total_llm_calls else 0):,}")
    print(f"📝 預估總 Input Tokens : {total_input_tokens:,}")
    print(f"📝 預估總 Output Tokens: {total_output_tokens:,}")
    print(f"💰 預估 API 費用 (以 $0.15/$0.6 每百萬 Token 計): ${total_cost_usd:.4f} USD")
    print("-" * 55)
    print(f"⏳ 預估花費時間 (使用本地 Ollama) : {time_ollama_seconds / 60:.2f} 分鐘 (約 {time_ollama_seconds / 3600:.2f} 小時)")
    print(f"⏳ 預估花費時間 (使用 OpenAI API) : {time_openai_seconds / 60:.2f} 分鐘 (約 {time_openai_seconds / 3600:.2f} 小時)")
    print("=" * 55)

if __name__ == "__main__":
    main()
