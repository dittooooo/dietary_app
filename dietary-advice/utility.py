# 份量代名詞
AMOUNT_KEYWORDS = ["少許", "適量", "依喜好", "適量即可", "酌量", "隨意"]
# 大概份量
AMOUNT_APPROX_KEYWORDS = ["約", "大約", "約略", "大概"]
# 食材名稱形容詞
INGREDIENT_NAME_ADJ_KEYWORDS = ["碎", "末", "絲", "片", "塊", "丁", "條", "段", "片", "切片", "切丁", "切絲"]
# TODO: 完成調味料判斷，並補充調味料列表
# 調味料
SEASONING_KEYWORDS = ["鹽", "糖", "醬", "醋", "油", "粉", "酒", "露", "汁", "膏", "蔥", "薑", "蒜"]
SEASONING_LIST = ["花椒", "八角", "桂皮", "香葉", "茴香", "孜然", "胡椒", "辣椒", "咖哩", "五香粉", "羅勒", "迷迭香", "百里香", "牛至", "月桂葉", "香菜籽", "孜然粉", "辣椒粉", "咖哩塊"]

def is_seasoning(ingredient_name):
    for keyword in SEASONING_KEYWORDS:
        if ingredient_name.find(keyword) != -1:
            return True
    return ingredient_name in SEASONING_LIST

def normalize_unit(unit):
    unit_map = {
        "g": "克",
        "克": "克",
        "公克": "克",
        "kg": "公斤",
        "公斤": "公斤",
        "cc": "毫升",
        "c.c.": "毫升",
        "ml": "毫升",
        "毫升": "毫升"
    }
    if unit in unit_map:
        return unit_map[unit]
    return unit