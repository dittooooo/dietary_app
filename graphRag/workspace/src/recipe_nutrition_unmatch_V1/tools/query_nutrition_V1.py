import json

def load_nutrition_data(filepath):
    """讀取 JSON 檔案並建立查詢索引"""
    try:
        with open(filepath, 'r', encoding='utf-8') as file:
            data = json.load(file)
            
        # 建立兩個索引字典
        name_index = {}         # 主鍵：樣品名稱
        common_name_index = {}  # 次鍵：俗名
        
        for item in data:
            # 1. 處理樣品名稱
            name = item.get("樣品名稱")
            if name:
                name_index[name] = item
            
            # 2. 處理俗名 (可能有多個，通常以逗號分隔)
            common_names_str = item.get("俗名")
            if common_names_str:
                # 替換全形逗號為半形，並以逗號切割
                c_names = common_names_str.replace("，", ",").split(",")
                for c_name in c_names:
                    c_name = c_name.strip() # 去除前後空白
                    if c_name:
                        # 將每個俗名對應到該筆資料
                        common_name_index[c_name] = item
                        
        return {
            "name_index": name_index,
            "common_name_index": common_name_index,
            "raw_data": data
        }
        
    except FileNotFoundError:
        print(f"錯誤：找不到檔案 '{filepath}'")
        return None
    except json.JSONDecodeError:
        print("錯誤：JSON 檔案格式不正確")
        return None

def query_ingredient(db, ingredient_name):
    """依照優先順序查詢食材資訊"""
    if not db:
        return "資料庫未建立"
    
    name_idx = db["name_index"]
    common_idx = db["common_name_index"]
    
    # 第一優先：完全比對「樣品名稱」
    if ingredient_name in name_idx:
        result = name_idx[ingredient_name]
        result['_match_type'] = '樣品名稱' # 標記比對來源，方便顯示
        return result
        
    # 第二優先：完全比對「俗名」
    if ingredient_name in common_idx:
        result = common_idx[ingredient_name]
        result['_match_type'] = '俗名'
        return result
        
    # 若皆找不到，提供模糊搜尋建議 (包含樣品名稱或俗名)
    suggestions = set() # 使用 set 避免重複
    for item in db["raw_data"]:
        name = item.get("樣品名稱", "")
        c_names = item.get("俗名", "")
        
        if ingredient_name in name or (c_names and ingredient_name in c_names):
            # 建議時顯示正式名稱，並附上俗名供參考
            display_name = name
            if c_names:
                display_name += f" (俗名: {c_names})"
            suggestions.add(display_name)
            
    if suggestions:
        return f"找不到完全相符的「{ingredient_name}」。您是不是要找：\n- " + "\n- ".join(suggestions)
        
    return f"找不到食材：「{ingredient_name}」"

# 測試與使用範例
if __name__ == "__main__":
    file_name = r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch\data\input\nutrition_data.json"
    
    print("正在載入資料庫...")
    my_nutrition_db = load_nutrition_data(file_name)
    
    if my_nutrition_db:
        print(f"載入成功！共載入 {len(my_nutrition_db['raw_data'])} 筆食材資料。\n")
        
        while True:
            target = input("請輸入你想查詢的食材名稱 (輸入 'q' 離開): ")
            
            if target.lower() == 'q':
                print("結束查詢。")
                break
                
            info = query_ingredient(my_nutrition_db, target)
            
            if isinstance(info, dict):
                print("-" * 40)
                match_type = info.pop('_match_type', '未知')
                print(f"✅ 查詢成功！(經由【{match_type}】符合)")
                print(f"【{info.get('樣品名稱')}】 營養資訊 (每100克):")
                
                # 若有俗名，也一併顯示出來讓使用者確認
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
            else:
                print(f"\n{info}\n")