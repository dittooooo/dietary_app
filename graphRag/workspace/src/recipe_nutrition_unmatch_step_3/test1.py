with open(r"C:\Users\PARALELL\Desktop\code4\workspace\src\recipe_nutrition_unmatch_RAG\data\input\2_nutrition_data_categorized_20260422_170816.json", "r", encoding="utf-8") as f:
    local_db = f.read()
    print("資料庫裡是否有字串 null？", '"整合編號": "null"' in local_db)
