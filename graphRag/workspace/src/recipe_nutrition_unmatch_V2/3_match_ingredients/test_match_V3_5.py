import json
import os
import glob
from typing import List, Dict, Optional
from dotenv import load_dotenv

try:
    from openai import OpenAI
    from tenacity import retry, stop_after_attempt, wait_exponential
except ImportError:
    print("Error: Missing required packages: pip install openai tenacity python-dotenv")
    exit(1)

load_dotenv()

# ================= Configuration =================
LLM_PROVIDER = "openai" 
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
{{"food_category": "挑選的分類名稱", "reason": "理由"}}
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
1. 湯類/清淡料理：若食譜是鮮魚湯、日式風格等，「油」通常指「大豆油、植物油、沙拉油」，不可選「人造奶油」或「香油」。
2. 中式熱炒：若有爆香，「油」多指「大豆油」或「豬油」。
3. 排除法：不要選擇與食譜風格嚴重衝突的油脂。

請從清單中選出一個最合理的官方名稱。回傳 JSON 格式（注意："matched_name" 必須「完全等於」上述【類別清單】中的某一個項目，絕對不可自行創造縮寫或清單上沒有的名稱）：
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
    # 自動尋找最新的精細化分類資料庫
    refined_files = glob.glob(os.path.join(base_dir, '2_enrich_nutrition', 'output', '2_nutrition_data_categorized_20260422_170816.json'))
    if refined_files:
        nutrition_file = refined_files[0]
    else:
        print("找不到細分資料庫，請先執行 2_nutrition_data_categorized_20260422_170816.json")
        return
        
    print(f"載入營養資料庫：{os.path.basename(nutrition_file)}...")
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

    print("\n" + "="*50)
    print("🚀 3_5 嚴格測試工具 (完全無模糊比對)")
    print(f"模式：{LLM_PROVIDER} ({model})")
    print("="*50)

    while True:
        target = input("\n請輸入食材名稱，輸入 'q' 離開 (如: 油): ").strip()
        if target.lower() == 'q': break
        recipe = input("請輸入食譜名稱 (如: 洋蔥鱸魚豆腐湯): ").strip()
        context = input("其他上下文食材 (如: 味噌, 鱸魚): ").strip()
        
        print(f"\n🧠 [正在執行 V3.5 嚴格匹配...]")
        
        # 1. Exact Match (全域精確匹配，包含俗名)
        if target in name_to_items:
            info = get_shortest_name_info(name_to_items[target])
            print(f"✨ [精確匹配成功]：{info['db_name']} (ID: {info['db_id']})")
            print(f"   理由：食材名稱完全符合資料庫中的名稱或俗名。")
            continue

        # 2. LLM 推斷流程
        cat = step1_get_category(client, model, target, recipe, categories_list)
        
        # 嚴格分類檢查：如果 LLM 回傳的分類不在清單中，直接視為失敗，不做任何模糊比對
        if cat and cat not in category_to_names:
            print(f"⚠️ [警告] LLM 產生了不存在的分類：「{cat}」，嚴格模式下拒絕匹配。")
            cat = None

        if cat:
            print(f"📂 [判定分類]：{cat}")
            item_names = category_to_names[cat]
            item_list_str = "、".join(item_names)
            llm_data = step2_get_item(client, model, target, recipe, context, cat, item_list_str)
            
            matched_name = None
            if llm_data and llm_data.get("matched_name"):
                matched_name = clean_name(llm_data["matched_name"])
                
            # 3. 嚴格檢查食材名稱
            if matched_name and matched_name in name_to_items:
                info = get_shortest_name_info(name_to_items[matched_name])
                print(f"✨ [推斷成功]：{info['db_name']} (ID: {info['db_id']})")
                print(f"   推斷理由：{llm_data.get('reason')}")
                print(f"   信心指數：{llm_data.get('confidence')}%")
            else:
                if matched_name:
                    print(f"❌ [失敗] LLM 推斷的食材「{matched_name}」不完全存在於資料庫中。")
                else:
                    print(f"❌ [失敗] LLM 未回傳任何匹配食材。")
        else:
            print(f"❌ [失敗] 無法判定合法分類。")

if __name__ == "__main__": main()
