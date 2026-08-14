import json
import os
import time
import re
from collections import defaultdict
from typing import List, Dict
from dotenv import load_dotenv

try:
    from openai import OpenAI
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
# =================================================

def setup_client():
    if LLM_PROVIDER == "ollama":
        return OpenAI(api_key="ollama", base_url=OLLAMA_BASE_URL), OLLAMA_MODEL
    else:
        return OpenAI(api_key=OPENAI_API_KEY), OPENAI_MODEL

def batch_list(lst, n):
    for i in range(0, len(lst), n):
        yield lst[i:i + n]

def refine_categories_batch(client, model, items: List[Dict]) -> Dict[str, str]:
    """使用 LLM 批次細分食材分類"""
    prompt = f"""
你是一個食材專家。請根據食材的「樣品名稱」與「原始分類」，將其重新歸類為更精確的「細分分類」。

### 分類原則：
1. 酒類：所有酒精飲品、料理酒。
2. 醬料/抹醬類：如醬油膏、沙拉醬、果醬、辣椒醬、金沙豆腐醬。
3. 粉末/調味粉類：如胡椒粉、糖粉、泡打粉、辣椒粉、滷味包。
4. 罐頭/醃漬類：如罐頭鮪魚、酸菜、泡菜、破布子罐頭。
5. 加工肉/水產類：如香腸、火腿、肉鬆、魚丸。
6. 沖泡飲品類：如咖啡粉、茶葉、奶粉。
7. 生鮮原型食材：如原始的蔬菜、肉類、水果、蛋類、豆類。

### 待處理資料：
{json.dumps([{"name": x['樣品名稱'], "orig": x['食品分類']} for x in items], ensure_ascii=False)}

### 請回傳 JSON (Key 為樣品名稱，Value 為新分類名稱)：
{{
  "樣品名稱": "新分類名稱"
}}
"""
    try:
        response = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            temperature=0,
            response_format={"type": "json_object"} if LLM_PROVIDER != "ollama" else None
        )
        content = response.choices[0].message.content.strip()
        return json.loads(content[content.find('{'):content.rfind('}')+1])
    except:
        return {}

def organize_nutrition_by_category():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    # 這裡我們讀取 2_enrich_nutrition 的輸出作為輸入，確保是在最新資料上操作
    input_file = os.path.join(base_dir, '2_enrich_nutrition', 'output')
    enriched_files = glob.glob(os.path.join(input_file, '2_nutrition_enriched_*.json'))
    if not enriched_files:
        print("找不到強化過的資料庫，請先執行 Step 2")
        return
    latest_input = max(enriched_files, key=os.path.getmtime)
    
    output_file = os.path.join(base_dir, '1_organize_nutrition_by_category', 'input', '1_nutrition_data_categorized_refined.json')

    print(f"Loading data from {latest_input}...")
    with open(latest_input, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # 攤平資料
    items_to_process = []
    if isinstance(data, dict):
        for items in data.values(): items_to_process.extend(items)
    else:
        items_to_process = data

    client, model = setup_client()
    new_mapping = {}
    batch_size = 40
    batches = list(batch_list(items_to_process, batch_size))
    
    print(f"Refining categories for {len(items_to_process)} items using LLM (Batches: {len(batches)})...")
    
    for batch in tqdm(batches, desc="Deep Categorizing"):
        result = refine_categories_batch(client, model, batch)
        new_mapping.update(result)
        if LLM_PROVIDER == "openai": time.sleep(0.5)

    # 重新組裝
    categorized_data = defaultdict(list)
    for item in items_to_process:
        name = item.get('樣品名稱')
        new_cat = new_mapping.get(name)
        if new_cat:
            item['食品分類'] = new_cat
        category = item.get('食品分類', '未分類')
        categorized_data[category].append(item)

    # Sort and Save
    sorted_categories = dict(sorted(categorized_data.items()))
    print(f"\nFinal Statistics ({len(sorted_categories)} categories):")
    for cat, items in sorted_categories.items():
        print(f" - {cat}: {len(items)} items")

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(sorted_categories, f, indent=2, ensure_ascii=False)

    print(f"\nSuccess! Saved to {output_file}")

import glob
if __name__ == "__main__":
    organize_nutrition_by_category()
