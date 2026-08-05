import json
import os
import time
import re
from datetime import datetime
from typing import List, Dict
from dotenv import load_dotenv
from openai import OpenAI

# Load configuration
load_dotenv()

LLM_PROVIDER = os.getenv("LLM_PROVIDER", "openai").lower()
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4.1-nano")

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434/v1")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "gemma3:4b")

# Initialize Client
if LLM_PROVIDER == "openai":
    client = OpenAI(api_key=OPENAI_API_KEY)
    model_name = OPENAI_MODEL
    print(f"Using OpenAI Provider ({model_name})")
else:
    client = OpenAI(base_url=OLLAMA_BASE_URL, api_key="ollama")
    model_name = OLLAMA_MODEL
    print(f"Using Ollama Provider ({model_name}) at {OLLAMA_BASE_URL}")

def batch_list(lst, n):
    for i in range(0, len(lst), n):
        yield lst[i:i + n]

def enrich_batch(items: List[Dict[str, str]]) -> Dict[str, List[str]]:
    prompt = f"""
你是一個食材專家兼資料清洗專家。請針對以下來自營養資料庫的內容，修訂並擴充其「俗名」（別名）。

### 重要原則：
1. **精確優先**：如果「樣品名稱」包含括號資訊（如：布丁、巧克力、低脂、脫脂、強化、寡醣），別名必須忠實反映這些特徵。
2. **避免過度籠統（重要）**：如果食材是特定的變體，別名**絕對不能**包含父類別的泛稱（例如：對於「脫脂強化鮮乳」，別名不應包含「牛奶」、「鮮乳」、「牛乳」），因為這會導致在自動匹配食譜時產生錯誤對應。
3. **場景化**：考慮這些食材在一般家常食譜中會如何被稱呼，生成 3-5 個精確的別名。
4. **審核現有俗名**：我會提供「現有俗名」，如果其中包含不夠精確或過於籠統的詞，請將其剃除，只保留精確且適合的。

### 待處理資料（JSON 格式）：
{json.dumps(items, ensure_ascii=False, indent=2)}

### 返回格式：
你**必須**返回一個 JSON 物件（Dictionary），Key 是原始的「樣品名稱」，Value 是包含別名的字串陣列。
不要包含 Markdown 格式，不要有額外解釋。

範例輸出：
{{
  "中脂調味保久乳(布丁)": ["布丁口味調味乳", "布丁奶", "布丁保久乳", "布丁牛奶"],
  "脫脂強化鮮乳(寡醣強化)": ["脫脂強化奶", "寡醣脫脂奶", "強化脫脂鮮乳"]
}}
"""
    try:
        response = client.chat.completions.create(
            model=model_name,
            messages=[
                {"role": "system", "content": "你是一個專業的營養與料理助手。你必須只回覆 JSON 物件格式，不要回覆列表。"},
                {"role": "user", "content": prompt}
            ],
            response_format={"type": "json_object"} if LLM_PROVIDER == "openai" else None
        )
        content = response.choices[0].message.content
        
        # Robust JSON extraction (look for either { or [ then parse)
        json_match = re.search(r'(\{.*\}|\[.*\])', content, re.DOTALL)
        if json_match:
            parsed = json.loads(json_match.group(0))
            # If it returned a list of objects, convert it to the expected dict format
            if isinstance(parsed, list):
                result = {}
                for item in parsed:
                    if isinstance(item, dict) and '樣品名稱' in item:
                        # Fallback if it used different keys for aliases
                        aliases = item.get('別名') or item.get('俗名') or item.get('aliases') or []
                        if isinstance(aliases, str): aliases = [a.strip() for a in aliases.split(',') if a.strip()]
                        result[item['樣品名稱']] = aliases
                return result
            return parsed
        else:
            print(f"Warning: No valid JSON found in response. Raw: {content[:100]}...")
            return {}
            
    except Exception as e:
        print(f"Error processing batch: {e}")
        return {}

def main():
    # Set this to True for a quick test run (only 1 batch)
    TEST_MODE = True 
    
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    input_file = os.path.join(base_dir, 'data', 'input', '1_nutrition_data_categorized.json')
    
    # Create output filename with timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_filename = f"2_nutrition_enriched_{timestamp}.json"
    output_file = os.path.join(base_dir, 'data', 'output', output_filename)

    if not os.path.exists(input_file):
        print(f"Error: {input_file} not found.")
        return

    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # Flatten and extract all unique formal names with descriptions
    items_to_enrich = []
    for category in data:
        for item in data[category]:
            # Each item is a dict with name and description for better context
            items_to_enrich.append({
                "樣品名稱": item['樣品名稱'],
                "內容物描述": item.get('內容物描述', ''),
                "現有俗名": item.get('俗名', '')
            })

    print(f"Found {len(items_to_enrich)} items to enrich.")
    
    # In a real run, we would batch them all. 
    # For this script, we'll implement a logical loop but with a safety break for testing if needed.
    enriched_mapping = {}
    batch_size = 20
    batches = list(batch_list(items_to_enrich, batch_size))
    
    print(f"Divided into {len(batches)} batches of {batch_size}.")
    
    # Process batches
    for i, batch in enumerate(batches):
        if TEST_MODE and i >= 1:
            print("Test mode enabled: Stopping after 1 batch.")
            break
            
        print(f"Processing batch {i+1}/{len(batches)}...")
        result = enrich_batch(batch)
        enriched_mapping.update(result)
        
        # Periodic save to avoid data loss
        if (i + 1) % 5 == 0:
            print("Auto-saving progress...")
            with open(output_file + ".tmp", 'w', encoding='utf-8') as f:
                json.dump(enriched_mapping, f, ensure_ascii=False, indent=2)
        
        # Avoid rate limits if using OpenAI
        if LLM_PROVIDER == "openai":
            time.sleep(1)

    # Merge enrichment back into original data
    print("Merging enriched aliases back into database...")
    for category in data:
        for item in data[category]:
            formal_name = item['樣品名稱']
            if formal_name in enriched_mapping:
                # Use AI result as the final cleaned list
                ai_aliases = enriched_mapping[formal_name]
                item['俗名'] = ",".join(ai_aliases)

    print(f"Saving final enriched data to {output_file}...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print("Success! Enrichment complete.")

if __name__ == "__main__":
    main()
