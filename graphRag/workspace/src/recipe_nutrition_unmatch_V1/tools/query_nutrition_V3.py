"""
程式名稱: 營養成分查詢系統
版本: V3

修改日誌:
- [2026-04-17] V1: 建立基礎查詢功能，以「樣品名稱」與「俗名」做精確比對與字串包含的模糊查詢。
- [2026-04-17] V2: 導入 LLM (大型語言模型) 輔助查詢。
                   解決 V1 中俗名比對導致的極端結果問題（例如搜「牛奶」卻跑出「布丁」）。
                   改為將所有資料庫食材名稱提供給 LLM，讓 LLM 依照常識進行 Top-K 推斷，
                   並在命令列輸出候選名單與挑選理由，最後讓使用者選擇想看的項目。
- [2026-04-17] V3: 模組化與物件導向封裝 (Class化)。
                   將核心功能封裝成 `NutritionQueryTool` 類別，方便在其他自動化 pipeline 
                   (如 analyze_unmatched_V3_3_three_pipeline.py) 中直接 import 使用，
                   並增加 verbose 參數以控制是否輸出終端機提示。
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
API_KEY = os.getenv("OPENAI_API_KEY", "YOUR_API_KEY_HERE") 
BASE_URL = "https://api.openai.com/v1" 
MODEL_NAME = "gpt-4.1-nano" # 使用平價且快速的模型即可
# ----------------------------------------

# 建立全域的 OpenAI Client
client = OpenAI(api_key=API_KEY, base_url=BASE_URL)


class NutritionQueryTool:
    def __init__(self, filepath):
        """初始化查詢工具，並載入營養資料庫"""
        self.filepath = filepath
        self.db = self._load_nutrition_data(filepath)
        
        # 預先將所有的樣品名稱抓出來存成列表，供 LLM 查詢使用
        if self.db:
            self.available_names = list(self.db.keys())
        else:
            self.available_names = []

    def _load_nutrition_data(self, filepath):
        """(內部方法) 讀取 JSON 檔案並建立查詢索引"""
        try:
            with open(filepath, 'r', encoding='utf-8') as file:
                data = json.load(file)
                
            name_index = {}
            for item in data:
                name = item.get("樣品名稱")
                if name:
                    name_index[name] = item
                    
            return name_index
        except Exception as e:
            print(f"載入資料庫發生錯誤：{e}")
            return None

    def ask_llm_for_top_k(self, user_input, k=5, verbose=False):
        """將使用者的查詢與可用的食材清單發送給 LLM，讓其挑選 Top-K"""
        if not self.available_names:
            if verbose: print("錯誤：資料庫尚未成功載入。")
            return []

        names_str = "、".join(self.available_names)
        
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
        
        if verbose:
            print(f"🧠 [LLM 思考中...] 正在根據常識分析「{user_input}」最適合的食材，請稍候...")
        
        try:
            response = client.chat.completions.create(
                model=MODEL_NAME,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.3
            )
            
            result_text = response.choices[0].message.content.strip()
            
            # 清理 Markdown 標籤
            result_text = re.sub(r"^```json", "", result_text, flags=re.MULTILINE)
            result_text = re.sub(r"^```", "", result_text, flags=re.MULTILINE)
            result_text = result_text.strip()
            
            # 解析並過濾掉不在資料庫內的幻覺名單
            top_k_results = json.loads(result_text)
            valid_results = [item for item in top_k_results if item.get('name') in self.db]
            
            return valid_results
        
        except Exception as e:
            if verbose: print(f"LLM 呼叫或解析失敗：{e}")
            return []

    def get_nutrition_info(self, sample_name):
        """根據樣品名稱，回傳完整的營養資訊 Dictionary"""
        return self.db.get(sample_name)

    def display_nutrition(self, sample_name):
        """(輔助方法) 在命令列印出單一食材的營養資訊"""
        info = self.get_nutrition_info(sample_name)
        if not info:
            print(f"資料庫中找不到：{sample_name}")
            return
            
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


# ================= 模組自測與互動模式 =================
# 當被其他程式 import 時，以下的程式碼不會自動執行
if __name__ == "__main__":
    if API_KEY == "YOUR_API_KEY_HERE":
        print("⚠️ 警告：請記得在環境變數或程式碼中填入你的 OpenAI API Key！\n")

    file_name = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch\data\input\nutrition_data.json"
    
    print("正在載入資料庫...")
    tool = NutritionQueryTool(file_name)
    
    if tool.available_names:
        print(f"載入成功！共載入 {len(tool.available_names)} 筆食材資料。\n")
        
        while True:
            target = input("請輸入你想查詢的食材名稱 (輸入 'q' 離開): ")
            
            if target.lower() == 'q':
                print("結束查詢。")
                break
            
            if not target.strip():
                continue
                
            # 測試時開啟 verbose=True 以顯示 LLM 狀態
            candidates = tool.ask_llm_for_top_k(target, k=5, verbose=True)
            
            if not candidates:
                print("無法取得建議或未找到相符資料，請重試。\n")
                continue
            
            print("\n" + "="*50)
            print(f"✨ LLM 為您找到最符合「{target}」的食材：")
            print("="*50)
            
            for i, cand in enumerate(candidates, 1):
                print(f"[{i}] 樣品名稱：{cand.get('name')}")
                print(f"    💡 挑選理由：{cand.get('reason')}")
                print("-" * 30)
            
            # 互動選擇
            while True:
                choice = input(f"\n請輸入號碼 (1-{len(candidates)}) 以查看詳細營養成分，或輸入 '0' 放棄並重新查詢: ")
                if choice == '0':
                    print("\n")
                    break
                
                try:
                    choice_idx = int(choice) - 1
                    if 0 <= choice_idx < len(candidates):
                        selected_name = candidates[choice_idx].get('name')
                        tool.display_nutrition(selected_name)
                        break
                    else:
                        print("號碼超出範圍，請重新輸入。")
                except ValueError:
                    print("請輸入有效的數字！")