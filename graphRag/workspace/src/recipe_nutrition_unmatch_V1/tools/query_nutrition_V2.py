"""
程式名稱: 營養成分查詢系統
版本: V2

修改日誌:
- [2026-04-17] V1: 建立基礎查詢功能，以「樣品名稱」與「俗名」做精確比對與字串包含的模糊查詢。
- [2026-04-17] V2: 導入 LLM (大型語言模型) 輔助查詢。
                   解決 V1 中俗名比對導致的極端結果問題（例如搜「牛奶」卻跑出「布丁」）。
                   改為將所有資料庫食材名稱提供給 LLM，讓 LLM 依照常識進行 Top-K 推斷，
                   並在命令列輸出候選名單與挑選理由，最後讓使用者選擇想看的項目。
"""

import json
import os
import re
from dotenv import load_dotenv
load_dotenv()
# 請確保已安裝：pip install openai
try:
    from openai import OpenAI
except ImportError:
    print("請先安裝 openai 套件: pip install openai")
    exit()

# ---------------- 配置設定 ----------------
# 請將這裡替換成你的 API Key，或設定在環境變數 OPENAI_API_KEY 中
API_KEY = os.getenv("OPENAI_API_KEY", "YOUR_API_KEY_HERE") 

# 若使用其他相容 OpenAI 格式的 API (例如 LM Studio, Ollama)，可修改 BASE_URL
BASE_URL = "https://api.openai.com/v1" 
MODEL_NAME = "gpt-4.1-nano" # 使用平價且快速的模型即可
# ----------------------------------------

client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

def load_nutrition_data(filepath):
    """讀取 JSON 檔案並建立查詢索引"""
    try:
        with open(filepath, 'r', encoding='utf-8') as file:
            data = json.load(file)
            
        # 以樣品名稱為主鍵建立字典
        name_index = {}
        for item in data:
            name = item.get("樣品名稱")
            if name:
                name_index[name] = item
                
        return name_index
    except Exception as e:
        print(f"載入資料庫發生錯誤：{e}")
        return None

def ask_llm_for_top_k(user_input, available_names, k=5):
    """將使用者的查詢與可用的食材清單發送給 LLM，讓其挑選 Top-K"""
    
    # 將所有名稱結合成一個長字串 (以逗號分隔)，作為 LLM 挑選的字典庫
    # 註：若資料量極大(如幾萬筆)，可能需要改用向量資料庫(Embedding)。
    # 但台灣食品營養資料庫通常僅約 2000~3000 筆，現代 LLM 的 Context Window 完全可以輕鬆處理。
    names_str = "、".join(available_names)
    
    prompt = f"""
    你是一個專業的營養學助手與資料庫檢索專家。
    我們有一個台灣食品營養資料庫，裡面包含以下食材名稱：
    [{names_str}]
    
    現在使用者想查詢的食材名稱是：「{user_input}」
    
    請依照人類的常識、烹飪習慣與營養學分類，從上述清單中挑選出最可能是使用者想尋找的 {k} 個「樣品名稱」。
    請務必：
    1. 完全使用清單內出現的名字，不要自己發明或修改字眼。
    2. 排除那些雖然含有關鍵字，但明顯不符合常識的加工品（除非使用者明確指名）。例如：使用者搜尋「牛奶」，應優先推薦「全脂鮮乳」、「低脂鮮乳」，而不是「調味保久乳(布丁)」。
    3. 給出挑選這個食材的理由。

    請一律以合法的 JSON 陣列格式回傳，不要加上任何 markdown 標記 (如 ```json) 或其他文字。
    回傳格式範例：
    [
      {{"name": "全脂鮮乳", "reason": "這是最常見的牛奶型態，符合一般人搜尋牛奶的直覺"}},
      {{"name": "低脂鮮乳", "reason": "對於注重健康的民眾，低脂鮮乳也是常見的牛奶選擇"}}
    ]
    """
    
    print("🧠 [LLM 思考中...] 正在根據常識分析最適合的食材，請稍候...")
    
    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.3 # 降低隨機性，讓推斷較為穩定精準
        )
        
        result_text = response.choices[0].message.content.strip()
        
        # 簡單清理可能帶有的 markdown block 標記
        result_text = re.sub(r"^```json", "", result_text, flags=re.MULTILINE)
        result_text = re.sub(r"^```", "", result_text, flags=re.MULTILINE)
        result_text = result_text.strip()
        
        # 解析 JSON
        top_k_results = json.loads(result_text)
        return top_k_results
    
    except Exception as e:
        print(f"LLM 呼叫或解析失敗：{e}")
        return []

def display_nutrition(info):
    """顯示單一食材的營養資訊"""
    print("-" * 40)
    print(f"【{info.get('樣品名稱')}】 營養資訊 (每100克):")
    if info.get('俗名'):
        print(f"俗名: {info.get('俗名')}")
    print(f"食品分類: {info.get('食品分類', '未知')}")
    print(f"熱量: {info.get('熱量(kcal)', 'N/A')} kcal")
    print(f"水分: {info.get('水分(g)', 'N/A')} g")
    print(f"粗蛋白: {info.get('粗蛋白(g)', 'N/A')} g")
    print(f"粗脂肪: {info.get('粗脂肪(g)', 'N/A')} g")
    print(f"總碳水化合物: {info.get('總碳水化合物(g)', 'N/A')} g")
    print(f"膳食纖維: {info.get('膳食纖維(g)', 'N/A')} g")
    print("-" * 40 + "\n")

# ================= 主程式 =================
if __name__ == "__main__":
    if API_KEY == "YOUR_API_KEY_HERE":
        print("⚠️ 警告：請記得在程式碼中填入你的 OpenAI API Key，否則無法使用 LLM 功能！\n")

    file_name = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch\data\input\nutrition_data.json"
    
    print("正在載入資料庫...")
    my_nutrition_db = load_nutrition_data(file_name)
    
    if my_nutrition_db:
        available_names_list = list(my_nutrition_db.keys())
        print(f"載入成功！共載入 {len(available_names_list)} 筆食材資料。\n")
        
        while True:
            target = input("請輸入你想查詢的食材名稱 (輸入 'q' 離開): ")
            
            if target.lower() == 'q':
                print("結束查詢。")
                break
            
            if not target.strip():
                continue
                
            # 呼叫 LLM 取得 Top-K 建議
            candidates = ask_llm_for_top_k(target, available_names_list, k=5)
            
            if not candidates:
                print("無法取得建議，請重試。\n")
                continue
            
            # 顯示 LLM 的挑選結果與理由
            print("\n" + "="*50)
            print(f"✨ LLM 為您找到最符合「{target}」的 Top-{len(candidates)} 食材：")
            print("="*50)
            
            valid_candidates = []
            for i, cand in enumerate(candidates, 1):
                name = cand.get('name', '未知名稱')
                reason = cand.get('reason', '無提供理由')
                
                # 確保 LLM 回傳的名字真的存在於資料庫中
                if name in my_nutrition_db:
                    valid_candidates.append(name)
                    print(f"[{len(valid_candidates)}] 樣品名稱：{name}")
                    print(f"    💡 挑選理由：{reason}")
                    print("-" * 30)
                else:
                    print(f"[X] LLM 建議了「{name}」，但該名稱不在資料庫中。(略過)")
            
            # 讓使用者選擇
            if valid_candidates:
                while True:
                    choice = input(f"\n請輸入號碼 (1-{len(valid_candidates)}) 以查看詳細營養成分，或輸入 '0' 放棄並重新查詢: ")
                    if choice == '0':
                        print("\n")
                        break
                    
                    try:
                        choice_idx = int(choice) - 1
                        if 0 <= choice_idx < len(valid_candidates):
                            selected_name = valid_candidates[choice_idx]
                            display_nutrition(my_nutrition_db[selected_name])
                            break
                        else:
                            print("號碼超出範圍，請重新輸入。")
                    except ValueError:
                        print("請輸入有效的數字！")
            else:
                print("LLM 未能找到資料庫內相符的食材。\n")