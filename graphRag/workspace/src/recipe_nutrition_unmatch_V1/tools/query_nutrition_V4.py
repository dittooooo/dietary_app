"""
程式名稱: 營養成分查詢系統 (NutritionQueryTool)
版本: V4 (加入 Hybrid Search 與分類上下文)
"""

import json
import os
import re
import difflib  # 新增：用於字串相似度計算
from dotenv import load_dotenv

load_dotenv()

try:
    from openai import OpenAI
except ImportError:
    print("請先安裝 openai 套件: pip install openai")
    exit()

# ---------------- 配置設定 ----------------
API_KEY = os.getenv("OPENAI_API_KEY", "YOUR_API_KEY_HERE") 
BASE_URL = "https://api.openai.com/v1" 
MODEL_NAME = "gpt-4.1-nano" 
# ----------------------------------------

client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

class NutritionQueryTool:
    def __init__(self, filepath):
        self.filepath = filepath
        self.db = self._load_nutrition_data(filepath)
        if self.db:
            self.available_names = list(self.db.keys())
        else:
            self.available_names = []

    def _load_nutrition_data(self, filepath):
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

    # 🌟 新增：第一階段演算法篩選
    def _get_pre_candidates(self, user_input, top_n=30):
        """(第一階段) 演算法字串相似度與包含測試，篩選出前 N 筆候選名單"""
        candidates = []
        for name, item in self.db.items():
            common_name = item.get("俗名", "") or ""
            category = item.get("食品分類", "未知")
            
            score = 0
            # 1. 完全比對或俗名完全比對 (權重最高)
            if user_input == name:
                score += 100
            if user_input in [c.strip() for c in common_name.replace("，", ",").split(",")]:
                score += 90
                
            # # 2. 包含字串 (權重次高)
            # if user_input in name:
            #     score += 50
            # if user_input in common_name:
            #     score += 40

            # 2. 包含字串 (權重次高)
            if user_input in name:
                # 核心改動：加入長度佔比加分 (最多加 30 分)
                # 例如搜「水」: 
                # 「純水」(2個字) 比例 1/2，可加 15 分 (總分 65)
                # 「香水芒果」(4個字) 比例 1/4，可加 7.5 分 (總分 57.5)
                ratio = len(user_input) / len(name)
                score += 50 + (ratio * 30)
                
            if user_input in common_name:
                ratio = len(user_input) / len(common_name) if len(common_name) > 0 else 0
                score += 40 + (ratio * 30)
                
            # 3. SequenceMatcher 相似度 (對短字串極為有效，例如 "鹽" 與 "岩鹽" 相似度很高)
            seq_score = difflib.SequenceMatcher(None, user_input, name).ratio() * 100
            score = max(score, seq_score)
            
            if score > 0:
                candidates.append({
                    "score": score,
                    "name": name,
                    "common_name": common_name,
                    "category": category
                })
                
        # 依分數排序，取前 N 名
        candidates.sort(key=lambda x: x["score"], reverse=True)
        return candidates[:top_n]

    # 🌟 修改：第二階段 LLM 推斷
    def ask_llm_for_top_k(self, user_input, k=5, verbose=False):
        if not self.available_names:
            if verbose: print("錯誤：資料庫尚未成功載入。")
            return []

        # 1. 取得 Top 30 演算法候選名單
        pre_candidates = self._get_pre_candidates(user_input, top_n=30)
        
        # 2. 組合給 LLM 看的上下文 (包含：名稱、分類、俗名)
        if not pre_candidates:
            # 極少數情況完全比對不到字元，退回全局盲測
            candidate_list_str = "、".join(self.available_names)
        else:
            lines = []
            for c in pre_candidates:
                # 讓 LLM 看見食品分類，這非常關鍵！
                lines.append(f"- 名稱: {c['name']} (分類: {c['category']}, 俗名: {c['common_name']})")
            candidate_list_str = "\n".join(lines)
        
        prompt = f"""
        你是一個專業的營養學助手與資料庫檢索專家。
        現在使用者想查詢的食材名稱是：「{user_input}」
        
        經過初步的演算法篩選，我們從台灣食品營養資料庫中找出了以下可能的候選名單：
        {candidate_list_str}
        
        請依照人類的常識、烹飪習慣與營養學分類，從上述清單中挑選出最可能是使用者想尋找的 {k} 個「名稱」。
        
        【重要挑選準則】：
        1. 參考「分類」：如果使用者搜尋基礎調味料(如：鹽、糖、油、蔥)，請優先挑選分類屬於「調味料及香辛料類」的項目。
        2. 尋找「本體」優先 (字義精準度)：如果使用者搜尋單一字詞(如：「水」、「雞」、「牛」)，請優先挑選字面意義最直接符合的基礎原態食物(如：「純水/飲用水」、「肉雞」、「牛肉」)，強烈排除只是名稱中「剛好包含該字」的其他加工品或無關食材(例如：搜尋「水」不可選「香水芒果」或「水蜜桃」；搜尋「雞」不要選「雞蛋布丁」)。
        3. 寧缺勿濫：若清單中「完全沒有」真正符合使用者搜尋意圖的合理食材，請直接略過不選（可能回傳少於 k 個，甚至回傳空陣列 []），絕對不可因為要湊數量而硬挑無關項目（例如搜「水」時，如果清單只有水蜜桃或水蕹菜，必須回傳空陣列）。
        4. 完全使用清單內出現的「名稱」，不要自己發明或修改字眼。
        5. 給出挑選這個食材的理由。

        請一律以合法的 JSON 陣列格式回傳，不要加上任何 markdown 標記。
        回傳格式範例：
        [
          {{"name": "岩鹽", "reason": "因為它屬於調味料，是最符合鹽的基礎型態"}},
          {{"name": "低鈉鹽", "reason": "這也是常見的鹽類替代品"}}
        ]
        """
        
        if verbose:
            print(f"🧠 [混合檢索中...] 演算法已鎖定 {len(pre_candidates)} 筆候選，正在交由 LLM 分析最適合「{user_input}」的食材...")
        
        try:
            response = client.chat.completions.create(
                model=MODEL_NAME,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1 # 降到更低，因為候選清單已經很精確了
            )
            
            result_text = response.choices[0].message.content.strip()
            result_text = re.sub(r"^```json", "", result_text, flags=re.MULTILINE)
            result_text = re.sub(r"^```", "", result_text, flags=re.MULTILINE)
            
            top_k_results = json.loads(result_text.strip())
            if isinstance(top_k_results, dict):
                top_k_results = [top_k_results]
                
            # 過濾確保 LLM 沒亂掰
            valid_results = [item for item in top_k_results if item.get('name') in self.db]
            return valid_results
        
        except Exception as e:
            if verbose: print(f"LLM 呼叫或解析失敗：{e}")
            return []

    def get_nutrition_info(self, sample_name):
        return self.db.get(sample_name)

    def display_nutrition(self, sample_name):
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
        print(f"粗蛋白: {info.get('粗蛋白(g)', 'N/A')} g")
        print(f"粗脂肪: {info.get('粗脂肪(g)', 'N/A')} g")
        print(f"總碳水化合物: {info.get('總碳水化合物(g)', 'N/A')} g")
        print("-" * 40 + "\n")

if __name__ == "__main__":
    file_name = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch\data\input\nutrition_data.json"
    tool = NutritionQueryTool(file_name)
    
    while True:
        target = input("\n請輸入你想查詢的食材名稱 (輸入 'q' 離開): ")
        if target.lower() == 'q': break
        if not target.strip(): continue
            
        candidates = tool.ask_llm_for_top_k(target, k=3, verbose=True)
        
        if not candidates:
            print("無法取得建議或未找到相符資料。\n")
            continue
            
        print("\n" + "="*50)
        print(f"✨ LLM 為您找到最符合「{target}」的食材：")
        print("="*50)
        for i, cand in enumerate(candidates, 1):
            print(f"[{i}] 樣品名稱：{cand.get('name')}")
            print(f"    💡 挑選理由：{cand.get('reason')}")
            print("-" * 30)