import json

# ==========================================
# 參數設定
# ==========================================
# 你的食譜檔案路徑
RECIPES_FILE = r'C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\recipes_20260424_090733.json'

# 費率設定 (每 100 萬 Token 的美金價格)
PRICE_PER_1M_INPUT = 0.10
PRICE_PER_1M_OUTPUT = 0.40

# 時間估算參數
# 假設循序呼叫時，每次呼叫 LLM 的平均延遲(秒)
AVG_API_LATENCY_SEC = 0.8

# ==========================================
# Token 粗略估算函式
# ==========================================


def estimate_tokens(text):
    # 對於 OpenAI (cl100k_base)，繁體中文 1 個字大約佔 1~2 個 Token。
    # 這裡採用較保守的估計：中文字數 * 1.5
    return int(len(text) * 1.5)

# ==========================================
# 主評估邏輯
# ==========================================


def run_estimation():
    with open(RECIPES_FILE, 'r', encoding='utf-8') as f:
        recipes = json.load(f)

    total_ingredients_count = 0
    unique_raw_ingredients = set()  # 用於評估「查詢前轉換」的快取
    unique_match_contexts = set()  # 用於評估「最終決斷」的快取

    total_input_tokens = 0
    total_output_tokens = 0
    total_api_calls = 0

    print("正在分析食譜與快取情境...")

    for recipe in recipes:
        recipe_name = recipe.get("name", "未命名食譜")
        ingredients = recipe.get("ingredients", [])

        all_ing_names = [ing.get("name", "")
                         for ing in ingredients if ing.get("name")]

        for i, target_name in enumerate(all_ing_names):
            total_ingredients_count += 1

            # --- 1. 評估「查詢前轉換 (get_core_ingredient)」 ---
            if target_name not in unique_raw_ingredients:
                unique_raw_ingredients.add(target_name)
                total_api_calls += 1

                # 模擬 Prompt 長度
                prompt1 = f"""
你是一個食材名稱標準化專家。請提取以下食譜食材的「核心食材名稱」。
規則：...（略）
原始食材：{target_name}
核心食材："""
                total_input_tokens += estimate_tokens(prompt1)
                # 預計輸出就是幾個字的核心食材
                total_output_tokens += estimate_tokens(target_name)

            # --- 2. 評估「最終決斷 (get_final_decision_from_llm)」 ---
            cache_key = f"{recipe_name}_{target_name}"
            if cache_key not in unique_match_contexts:
                unique_match_contexts.add(cache_key)
                total_api_calls += 1

                context_others = [name for j,
                                  name in enumerate(all_ing_names) if j != i]
                # 模擬包含 10 個候選名單(Top-K=10) 的超長 Prompt
                candidates_mock = "1. 分類：某分類。名稱：某名稱。俗名：某俗名\n" * 10
                prompt2 = f"""
你是一個專業的營養學資料對應專家。請根據食譜的上下文...
【食譜資訊】
食譜名稱：{recipe_name}
其他共演食材：{', '.join(context_others)}
【目標食材】
原始名稱：{target_name}
【候選清單】
{candidates_mock}
【任務規則】...（略）
"""
                total_input_tokens += estimate_tokens(prompt2)
                # 預計輸出就是選中的名稱
                total_output_tokens += 10  # 大約幾個字

    # ==========================================
    # 計算成本與時間
    # ==========================================
    cost_input = (total_input_tokens / 1_000_000) * PRICE_PER_1M_INPUT
    cost_output = (total_output_tokens / 1_000_000) * PRICE_PER_1M_OUTPUT
    total_cost_usd = cost_input + cost_output

    # 計算總耗時 (秒 -> 分鐘)
    total_time_sec = total_api_calls * AVG_API_LATENCY_SEC
    total_time_min = total_time_sec / 60

    print("\n" + "="*50)
    print("📊 批次處理成本與時間估算報告 📊")
    print("="*50)
    print(f"總共處理食譜數： {len(recipes)} 道")
    print(f"總共掃描食材數： {total_ingredients_count} 項")
    print("-" * 50)
    print(f"✨ 快取發揮作用：")
    print(
        f"  - 需淨化的獨特食材數： {len(unique_raw_ingredients)} 次 (省去 {total_ingredients_count - len(unique_raw_ingredients)} 次重複呼叫)")
    print(
        f"  - 需決斷的獨特情境數： {len(unique_match_contexts)} 次 (省去 {total_ingredients_count - len(unique_match_contexts)} 次重複呼叫)")
    print(f"  - 總計 LLM API 呼叫次數： {total_api_calls} 次")
    print("-" * 50)
    print(f"🪙 Token 消耗量：")
    print(f"  - 預估 Input Token：  約 {total_input_tokens:,} tokens")
    print(f"  - 預估 Output Token： 約 {total_output_tokens:,} tokens")
    print("-" * 50)
    print(f"⏱️ 預估耗時 (循序單線程)：")
    print(f"  - 約 {total_time_sec:.0f} 秒 (約 {total_time_min:.1f} 分鐘)")
    print(f"    *若你未來改用異步或多執行緒，時間可大幅縮短。")
    print("-" * 50)
    print(f"💰 預估 API 總花費：")
    print(f"  - Input 花費：  ${cost_input:.5f} USD")
    print(f"  - Output 花費： ${cost_output:.5f} USD")
    print(f"  - 總計花費：    ${total_cost_usd:.5f} USD")
    print("="*50)


if __name__ == "__main__":
    run_estimation()
