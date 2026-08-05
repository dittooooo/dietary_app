# 計算會花費多少token的程式

import json
import os
import tiktoken
from typing import List, Dict

# 配置與費率 (gpt-4.1-nano)
INPUT_RATE_PER_1M = 0.10
OUTPUT_RATE_PER_1M = 0.40
BATCH_SIZE = 20

def estimate_tokens():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    input_file = os.path.join(base_dir, 'data', 'input', '1_nutrition_data_categorized.json')

    if not os.path.exists(input_file):
        print(f"Error: {input_file} not found.")
        return

    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # 提取待處理資料
    items_to_enrich = []
    for category in data:
        for item in data[category]:
            items_to_enrich.append({
                "樣品名稱": item['樣品名稱'],
                "內容物描述": item.get('內容物描述', ''),
                "現有俗名": item.get('俗名', '')
            })

    total_items = len(items_to_enrich)
    num_batches = (total_items + BATCH_SIZE - 1) // BATCH_SIZE

    # 使用 o200k_base (GPT-4o 常用) 或 cl100k_base (GPT-4 常用)
    # 這裡選用 cl100k_base 作為通用估算
    encoding = tiktoken.get_encoding("cl100k_base")

    total_input_tokens = 0
    total_output_tokens = 0

    # 模擬 Prompt 結構估算 Input
    system_prompt = "你是一個專業的營養與料理助手。你必須只回覆 JSON 物件格式，不要回覆列表。"
    instruction_template = "你是一個食材專家兼資料清洗專家。請針對以下來自營養資料庫的內容，修訂並擴充其「俗名」（別名）。..." # 簡略代表
    
    base_prompt_tokens = len(encoding.encode(system_prompt + instruction_template))

    for i in range(0, total_items, BATCH_SIZE):
        batch = items_to_enrich[i : i + BATCH_SIZE]
        batch_json = json.dumps(batch, ensure_ascii=False)
        batch_tokens = len(encoding.encode(batch_json))
        
        # 每批次 Input = 基礎指令 + 批次資料
        total_input_tokens += (base_prompt_tokens + batch_tokens)
        
        # 預估 Output: 假設平均每個食材生成 60 tokens 的回傳內容
        total_output_tokens += (len(batch) * 60)

    # 計算費用
    input_cost = (total_input_tokens / 1_000_000) * INPUT_RATE_PER_1M
    output_cost = (total_output_tokens / 1_000_000) * OUTPUT_RATE_PER_1M
    total_cost = input_cost + output_cost

    print("="*40)
    print(f"食材總數: {total_items}")
    print(f"批次總數: {num_batches} (每批 {BATCH_SIZE} 筆)")
    print("-" * 40)
    print(f"預估總輸入 Token: {total_input_tokens:,}")
    print(f"預估總輸出 Token: {total_output_tokens:,}")
    print("-" * 40)
    print(f"預估輸入費用: ${input_cost:.6f} USD")
    print(f"預估輸出費用: ${output_cost:.6f} USD")
    print(f"預估總費用:   ${total_cost:.4f} USD (約 {total_cost*32:.2f} TWD)")
    print("="*40)

if __name__ == "__main__":
    estimate_tokens()
