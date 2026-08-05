import json
from collections import defaultdict
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "output"
RULES_OUTPUT_PATH = BASE_DIR / "chronic_disease_rules.json"
NUTRIENT_INDEX_OUTPUT_PATH = BASE_DIR / "nutrient_rules_index.json"


RELATION_TYPES = ["recommend", "limit", "prohibit"]

DISEASE_ROWS = [
    ("hypertension", "Hypertension", "高血壓"),
    ("hyperlipidemia", "Hyperlipidemia", "高血脂"),
    ("diabetes_mellitus", "Diabetes Mellitus", "糖尿病"),
    ("cardiovascular_disease", "Cardiovascular Disease", "心血管疾病"),
    ("chronic_kidney_disease", "Chronic Kidney Disease", "慢性腎臟病"),
    ("stroke", "Stroke", "腦中風"),
    ("metabolic_syndrome", "Metabolic Syndrome", "代謝症候群"),
    ("gout", "Gout", "痛風"),
    ("hyperuricemia", "Hyperuricemia", "高尿酸血症"),
    ("gastroesophageal_reflux_disease", "Gastroesophageal Reflux Disease", "胃食道逆流"),
]

COMMON_RISK_NOTES = [
    "此資料用於飲食建議與知識圖譜推論，不可取代醫師診斷、藥物治療或營養師個別化評估。",
    "若使用者同時有其他慢性疾病，應合併其他疾病規則重新加權，並優先處理高風險限制條件。",
]


def rule(
    relation,
    nutrient_zh,
    nutrient_en,
    target_rule,
    food_level_rule,
    example_foods,
    reason,
    sources,
):
    return {
        "relation": relation,
        "nutrient_name_zh": nutrient_zh,
        "nutrient_name_en": nutrient_en,
        "target_rule": target_rule,
        "food_level_rule": food_level_rule,
        "example_foods": example_foods,
        "reason": reason,
        "sources": sources,
    }


def target(direction, unit=None, daily_target=None, daily_limit=None, weekly_target=None, max=None, optimal=None, note=None):
    return {
        "daily_target": daily_target,
        "daily_limit": daily_limit,
        "weekly_target": weekly_target,
        "max": max,
        "optimal": optimal,
        "unit": unit,
        "direction": direction,
        "note": note,
    }


def level(level_name, operator=None, amount=None, unit=None, condition=None, note=None):
    return {
        "basis": "per_100g",
        "level": level_name,
        "operator": operator,
        "amount": amount,
        "unit": unit,
        "condition": condition,
        "note": note or "此為推薦系統判斷門檻，需依台灣食品成分資料庫與實際料理資料校正。",
    }


def source(file_name, evidence):
    return {"source_file": file_name, "evidence": evidence}


SOURCES = {
    "ms": "代謝症候群學習手冊.txt",
    "diet": "慢性病飲食守則.md",
    "principle": "慢性病飲食調理基本原則.md",
    "ckd": "自主健康保腎手冊.txt",
}


DIET_PATTERNS = {
    "hypertension": {
        "recommended_patterns": ["DASH", "低鈉高纖均衡飲食"],
        "core_principle": "限制鈉與高油脂食物，增加蔬菜水果、膳食纖維、鉀、鈣、鎂，並避免過量飲酒。",
    },
    "hyperlipidemia": {
        "recommended_patterns": ["地中海飲食", "高纖低飽和脂肪飲食"],
        "core_principle": "提高膳食纖維、可溶性纖維、Omega-3 與不飽和脂肪，限制飽和脂肪、反式脂肪、膽固醇、添加糖與酒精。",
    },
    "diabetes_mellitus": {
        "recommended_patterns": ["低 GI 均衡飲食", "高纖控醣飲食"],
        "core_principle": "定時定量，控制總碳水化合物與添加糖，選擇低 GI、高纖、優質蛋白質與健康脂肪。",
    },
    "cardiovascular_disease": {
        "recommended_patterns": ["地中海飲食", "DASH"],
        "core_principle": "以控制血壓、血脂、血糖與體重為核心，限制鈉、飽和脂肪、反式脂肪、膽固醇與添加糖。",
    },
    "chronic_kidney_disease": {
        "recommended_patterns": ["腎臟病分期飲食", "低鈉控磷控鉀飲食"],
        "core_principle": "依腎功能分期、是否透析、血鉀血磷與尿量調整蛋白質、鈉、鉀、磷與水分，並維持足夠熱量。",
    },
    "stroke": {
        "recommended_patterns": ["DASH", "地中海飲食"],
        "core_principle": "降低腦血管再發風險，控制血壓、血脂、血糖與心血管危險因子。",
    },
    "metabolic_syndrome": {
        "recommended_patterns": ["三低一高飲食", "均衡六大類飲食"],
        "core_principle": "低油、低糖、低鹽、高纖，搭配體重控制、規律運動與限制酒精。",
    },
    "gout": {
        "recommended_patterns": ["低普林飲食", "高水分低酒精飲食"],
        "core_principle": "限制普林、酒精與果糖，增加水分，以降低尿酸生成並促進尿酸排除。",
    },
    "hyperuricemia": {
        "recommended_patterns": ["低普林飲食", "尿酸控制飲食"],
        "core_principle": "限制普林、酒精與果糖，增加水分，目標是預防尿酸升高與痛風發作。",
    },
    "gastroesophageal_reflux_disease": {
        "recommended_patterns": ["低脂低刺激飲食", "症狀觸發食物管理"],
        "core_principle": "限制高脂、咖啡因、酒精、辛辣、酸性與碳酸飲品，依個人症狀觸發反應調整。",
    },
}


RULES_BY_DISEASE = {
    "hypertension": [
        rule("limit", "鈉", "Sodium", target("decrease", "mg/day", daily_limit="2000 mg/day 或 5 g salt/day", note="文件明確提到限制鹽分每日 < 5g；鈉上限需依資料庫校正。"), level("high", ">=", 600, "mg", "high_sodium"), ["鹽", "醬油", "味精", "烏醋", "麵線", "油麵", "香腸", "火腿", "罐頭食品", "醃製食品"], "鈉攝取過多會使血壓上升，增加心血管與腎臟負擔。", [source(SOURCES["diet"], "高血壓飲食原則：減少鈉攝取，少用含鈉調味料，加工食品含鈉量高應儘量少用。"), source(SOURCES["principle"], "高血壓飲食調理建議：限制鹽分（每日 < 5g）、避免醃製和加工食品。")]),
        rule("recommend", "鉀", "Potassium", target("increase", None, daily_target="需依個人腎功能與資料庫校正", note="慢性腎臟病或高血鉀者不可直接套用。"), level("rich", ">=", None, "mg", "high_potassium"), ["香蕉", "番茄", "菠菜", "新鮮蔬果"], "鉀可幫助血壓控制，但需排除腎功能不佳或高血鉀風險。", [source(SOURCES["diet"], "飲食中的鉀離子有對抗高血壓的保護作用，新鮮蔬果多為高鉀食物。"), source(SOURCES["principle"], "高血壓飲食調理建議：多吃高鉀食物。")]),
        rule("recommend", "鈣", "Calcium", target("increase", None, daily_target="需依資料庫校正", note="以食物來源為主。"), level("source", ">=", None, "mg", "calcium_source"), ["低脂奶類", "小魚干", "豆乾", "豆腐", "深綠色蔬菜"], "足夠鈣攝取與血壓調節相關，可作為高血壓飲食輔助。", [source(SOURCES["diet"], "含鈣離子較多的食物對於高血壓有幫助。")]),
        rule("recommend", "鎂", "Magnesium", target("increase", None, daily_target="需依資料庫校正", note="以全穀、堅果、蔬菜等食物來源為主。"), level("source", ">=", None, "mg", "magnesium_source"), ["海藻", "髮菜", "海鮮", "堅果類", "全穀類", "綠色蔬菜"], "鎂參與血管張力與代謝調節，文件列為高血壓有幫助的營養成分。", [source(SOURCES["diet"], "含鎂離子較多的食物對於高血壓也有幫助。")]),
        rule("recommend", "膳食纖維", "Dietary Fiber", target("increase", "g/day", daily_target="需依資料庫校正", note="以蔬菜、全穀與水果增加纖維。"), level("rich", ">=", 3, "g", "high_fiber"), ["蔬菜", "水果", "全穀類"], "膳食纖維可幫助排便順暢，降低用力解便造成血壓上升的風險。", [source(SOURCES["diet"], "多攝取纖維可使排便順暢，避免因用力解便而使血壓上升。")]),
        rule("limit", "飽和脂肪", "Saturated Fat", target("decrease", "% energy", daily_limit="需依資料庫校正", note="以植物油取代動物性油脂。"), level("high", ">=", None, "g", "high_saturated_fat"), ["肥肉", "豬皮", "雞皮", "油酥糕點", "豬油", "牛油"], "飽和脂肪與高油飲食會提高心血管風險，高血壓者需控制總心血管風險。", [source(SOURCES["diet"], "高血壓飲食原則：低油飲食，避免肥肉、豬（雞）皮及油酥糕點。")]),
        rule("limit", "酒精", "Alcohol", target("decrease", "alcohol equivalent/day", daily_limit="女性 <= 1；男性 <= 2", note="高血壓與心血管風險者建議限制或避免過量飲酒。"), level("contains", ">", 0, "g", "alcohol_containing"), ["啤酒", "米酒", "紹興酒", "高粱酒", "葡萄酒", "威士忌"], "酒精會影響血壓與心血管風險，文件建議戒菸酒與適量飲酒。", [source(SOURCES["diet"], "高血壓飲食原則：適當調整生活型態，如戒菸酒。"), source(SOURCES["ms"], "女性每日不宜超過1個酒精當量，男性每日不宜超過2個酒精當量。")]),
        rule("recommend", "不飽和脂肪", "Unsaturated Fat", target("replace", None, daily_target="需依資料庫校正", note="用植物油與魚類等健康脂肪取代動物油脂。"), level("source", ">=", None, "g", "unsaturated_fat_source"), ["橄欖油", "菜籽油", "深海魚"], "以不飽和脂肪取代動物性油脂可降低整體心血管風險。", [source(SOURCES["diet"], "烹調用油少用動物性油脂，以植物油烹調。"), source(SOURCES["principle"], "高血壓飲食調理建議：適量攝取健康脂肪，如橄欖油、深海魚。")]),
    ],
    "hyperlipidemia": [
        rule("recommend", "可溶性膳食纖維", "Soluble Fiber", target("increase", "g/day", daily_target="5-10 g/day", note="此數值為常用建議範圍，需依資料庫與個別需求校正。"), level("rich", ">=", 3, "g", "soluble_or_total_fiber_rich"), ["燕麥", "菇類", "木耳", "海帶", "山藥", "秋葵", "全穀雜糧", "豆類"], "可溶性纖維可吸附油脂與膽固醇並由糞便排出，有助改善 LDL-C。", [source(SOURCES["ms"], "水溶性纖維質如燕麥、菇類、木耳、海帶、山藥、秋葵，可減少血液中膽固醇。"), source(SOURCES["diet"], "高膽固醇血症多選用富含高纖維的食物。")]),
        rule("recommend", "Omega-3 脂肪酸", "Omega-3 Fatty Acids", target("increase", None, daily_target="需依資料庫校正", note="以魚類與堅果種子等食物來源為主。"), level("source", ">=", None, "g", "omega_3_source"), ["秋刀魚", "鮭魚", "鯖魚", "鰻魚", "白鯧魚", "牡蠣", "核桃", "亞麻籽", "奇亞籽"], "Omega-3 脂肪酸有助血脂管理並降低心血管風險。", [source(SOURCES["diet"], "高三酸甘油酯可多攝取富含 omega-3 脂肪酸的魚類。"), source(SOURCES["principle"], "高血脂飲食調理建議：增加攝取 Omega-3。")]),
        rule("recommend", "不飽和脂肪", "Unsaturated Fat", target("replace", None, daily_target="需依資料庫校正", note="用單元不飽和脂肪與植物油取代飽和脂肪。"), level("source", ">=", None, "g", "unsaturated_fat_source"), ["橄欖油", "芥花油", "酪梨油", "堅果", "亞麻籽", "奇亞籽"], "不飽和脂肪可作為較佳油脂來源，協助取代飽和脂肪並保護心血管。", [source(SOURCES["diet"], "炒菜多選用單元不飽和脂肪酸含量高的油脂，如橄欖油、芥花油。"), source(SOURCES["principle"], "高血脂患者適合選擇健康脂肪。")]),
        rule("limit", "飽和脂肪", "Saturated Fat", target("decrease", "% energy", daily_limit="需依資料庫校正", note="避免以過度精準數值套用所有使用者。"), level("high", ">=", None, "g", "high_saturated_fat"), ["豬油", "奶油", "牛油", "椰子油", "肥肉", "雞皮", "豬皮", "鴨皮", "焢肉", "三層肉"], "飽和脂肪會提高 LDL-C，是高血脂需限制的主要營養因素。", [source(SOURCES["diet"], "高膽固醇血症應少吃含有飽和脂肪酸的食物。"), source(SOURCES["principle"], "高血脂飲食調理建議：減少飽和脂肪。")]),
        rule("prohibit", "反式脂肪", "Trans Fat", target("avoid", "g/day", daily_limit="越低越好", note="推薦系統視為高風險應強烈避免。"), level("contains", ">", 0, "g", "trans_fat_containing"), ["酥油", "白油", "乳瑪琳", "人造奶油", "甜鹹麵包", "油酥糕餅", "蛋糕", "餅乾", "速食"], "反式脂肪會提高心血管疾病風險，對高血脂屬高風險項目。", [source(SOURCES["diet"], "少吃含有反式脂肪酸的食物，如酥油、白油、乳瑪琳、糕餅。"), source(SOURCES["ms"], "避免攝取反式脂肪酸高的食物。")]),
        rule("limit", "膽固醇", "Cholesterol", target("decrease", "mg/day", daily_limit="需依資料庫校正", note="血脂異常者需依個人狀況調整。"), level("high", ">=", None, "mg", "high_cholesterol"), ["動物內臟", "蛋黃", "魚卵", "蟹黃"], "高膽固醇食物可能不利血膽固醇控制，需與飽和脂肪一起管理。", [source(SOURCES["ms"], "減少吃富含飽和脂肪酸及膽固醇的食物，動物內臟、蛋黃、魚卵、蟹黃膽固醇含量高。")]),
        rule("limit", "添加糖", "Added Sugar", target("decrease", "g/day", daily_limit="需依資料庫校正", note="尤其高三酸甘油酯者需限制含糖飲料與甜食。"), level("high", ">=", None, "g", "added_sugar_high"), ["精緻甜食", "含糖飲料", "糖果", "餅乾", "水果罐頭", "市售茶飲", "汽水", "可樂"], "添加糖與高果糖飲料會造成血脂升高，特別影響三酸甘油酯。", [source(SOURCES["diet"], "高三酸甘油酯應避免精緻甜食、含蔗糖或果糖飲料。"), source(SOURCES["ms"], "高糖甜點及含糖飲料不利血糖控制，也會造成血脂升高。")]),
        rule("limit", "鈉", "Sodium", target("decrease", "mg/day", daily_limit="需依資料庫校正", note="高血脂常合併心血管風險，建議限制高鈉加工食品。"), level("high", ">=", 600, "mg", "high_sodium"), ["加工食品", "香腸", "火腿", "速食", "罐頭食品"], "高血脂常與心血管疾病風險共存，限制鈉有助降低整體心血管負擔。", [source(SOURCES["principle"], "高血脂可能導致動脈硬化、心血管疾病、中風等風險。"), source(SOURCES["ms"], "健康飲食行動方案包含低鹽，減少加工食品與調味醬料。")]),
        rule("limit", "酒精", "Alcohol", target("decrease", None, daily_limit="需依資料庫校正；高三酸甘油酯者不宜飲酒", note="若三酸甘油酯偏高，酒精應列為高風險。"), level("contains", ">", 0, "g", "alcohol_containing"), ["酒類", "啤酒"], "酒精會影響三酸甘油酯控制，文件明確指出高三酸甘油酯不宜飲酒。", [source(SOURCES["diet"], "高三酸甘油酯飲食原則：不宜飲酒。")]),
    ],
    "diabetes_mellitus": [
        rule("limit", "添加糖", "Added Sugar", target("decrease", "g/day", daily_limit="需依資料庫校正", note="低血糖處理例外，不可把急救糖分規則套成日常建議。"), level("high", ">=", None, "g", "added_sugar_high"), ["含糖飲料", "甜點", "糖果", "餅乾", "水果罐頭", "蛋糕", "果汁", "冰淇淋"], "添加糖會使血糖快速上升，增加血糖控制困難。", [source(SOURCES["diet"], "避免攝取精緻甜食、含蔗糖或果糖飲料、糖果或餅乾等加糖製品。"), source(SOURCES["principle"], "糖尿病患者避免含糖飲料及甜食。")]),
        rule("limit", "精製碳水化合物", "Refined Carbohydrate", target("decrease", None, daily_limit="需依資料庫校正", note="需同時管理總碳水化合物與 GI 值。"), level("high", ">=", None, "g", "refined_carbohydrate_high"), ["白飯", "白麵條", "白麵包", "玉米粉", "馬鈴薯", "精製糖類"], "精製碳水化合物與高 GI 食物容易造成血糖快速上升。", [source(SOURCES["principle"], "糖尿病患者避免高 GI 食物與精製糖類，如白飯、白麵條、白麵包。")]),
        rule("recommend", "膳食纖維", "Dietary Fiber", target("increase", "g/day", daily_target="需依資料庫校正", note="優先從全穀、豆類、蔬菜、堅果與種子取得。"), level("rich", ">=", 3, "g", "high_fiber"), ["全穀類", "燕麥", "糙米", "黑米", "藜麥", "紅豆", "綠豆", "黑豆", "鷹嘴豆", "菠菜", "苦瓜"], "膳食纖維可延緩葡萄糖吸收，幫助穩定血糖。", [source(SOURCES["diet"], "糖尿病飲食原則：儘量選擇高纖維食物。"), source(SOURCES["principle"], "高纖維食物可延緩葡萄糖吸收。")]),
        rule("limit", "鈉", "Sodium", target("decrease", "mg/day", daily_limit="需依資料庫校正", note="糖尿病併發高血壓或腎臟病時需更嚴格加權。"), level("high", ">=", 600, "mg", "high_sodium"), ["醃漬食品", "泡菜", "鹹魚", "罐頭食品", "加工肉品"], "高鈉食品會影響血壓並增加糖尿病併發症風險。", [source(SOURCES["principle"], "糖尿病患者避免高鈉食品，會影響血壓，增加糖尿病併發症風險。"), source(SOURCES["diet"], "糖尿病烹調遵守少油、少鹽、少糖。")]),
        rule("limit", "飽和脂肪", "Saturated Fat", target("decrease", "% energy", daily_limit="需依資料庫校正", note="若血液膽固醇濃度過高，需減少飽和脂肪酸。"), level("high", ">=", None, "g", "high_saturated_fat"), ["肥肉", "動物油", "動物皮", "全脂奶", "椰子油", "豬皮", "雞皮", "鴨皮", "魚皮"], "飽和脂肪會增加血脂與胰島素阻抗相關風險，糖尿病需管理心血管併發症。", [source(SOURCES["diet"], "若血液膽固醇濃度過高，需減少飽和脂肪酸攝取。")]),
        rule("recommend", "低升糖指數碳水化合物", "Low Glycemic Index Carbohydrate", target("replace", None, daily_target="需依個人醣量計畫校正", note="不是無限制增加，需配合總醣量。"), level("preferred", None, None, None, "low_gi"), ["糙米", "燕麥", "藜麥", "全麥麵包", "地瓜", "南瓜", "綠豆", "紅豆", "鷹嘴豆"], "低 GI 碳水化合物較能穩定餐後血糖。", [source(SOURCES["principle"], "糖尿病飲食調理建議：選擇低升糖指數（GI）的食物。")]),
        rule("recommend", "不飽和脂肪", "Unsaturated Fat", target("replace", None, daily_target="需依熱量需求校正", note="堅果與油脂仍需控制總熱量。"), level("source", ">=", None, "g", "unsaturated_fat_source"), ["橄欖油", "菜籽油", "酪梨", "堅果", "深海魚"], "健康脂肪可減少血糖波動並改善胰島素敏感性。", [source(SOURCES["diet"], "炒菜多選用單元不飽和脂肪酸含量高油脂如橄欖油、菜籽油。"), source(SOURCES["principle"], "健康脂肪可改善胰島素敏感性。")]),
        rule("limit", "酒精", "Alcohol", target("decrease", None, daily_limit="需依醫囑與藥物使用校正", note="使用胰島素或降血糖藥者需注意低血糖風險。"), level("contains", ">", 0, "g", "alcohol_containing"), ["啤酒", "調酒", "高糖含量酒類"], "酒精會影響血糖穩定，空腹飲酒會增加低血糖風險。", [source(SOURCES["diet"], "糖尿病儘量避免喝酒，若飲酒需限量並避免空腹喝酒。"), source(SOURCES["principle"], "避免過量飲酒，影響血糖穩定。")]),
    ],
    "cardiovascular_disease": [
        rule("limit", "鈉", "Sodium", target("decrease", "mg/day", daily_limit="需依資料庫校正", note="控制血壓是心血管風險管理核心。"), level("high", ">=", 600, "mg", "high_sodium"), ["鹽", "醬油", "調味醬料", "醃製食品", "加工食品", "罐頭食品"], "高鈉攝取會使血壓上升，增加心血管疾病風險。", [source(SOURCES["principle"], "選擇低鈉食物可避免血壓升高、增加心血管疾病風險。"), source(SOURCES["ms"], "切忌吃太鹹，減少鹽、醬油、各式醬料及加工食品。")]),
        rule("limit", "飽和脂肪", "Saturated Fat", target("decrease", "% energy", daily_limit="需依資料庫校正", note="以不飽和脂肪取代。"), level("high", ">=", None, "g", "high_saturated_fat"), ["肥肉", "動物油脂", "奶油", "椰子油", "棕櫚油", "全脂奶"], "飽和脂肪會提高 LDL-C 並增加動脈硬化與心血管風險。", [source(SOURCES["ms"], "減少吃富含飽和脂肪酸及膽固醇的食物。"), source(SOURCES["principle"], "高血脂可能導致動脈硬化、心血管疾病與中風。")]),
        rule("prohibit", "反式脂肪", "Trans Fat", target("avoid", "g/day", daily_limit="越低越好", note="推薦系統視為高風險。"), level("contains", ">", 0, "g", "trans_fat_containing"), ["酥油", "硬乳瑪琳", "氫化油", "糕餅", "速食", "人造奶油"], "反式脂肪會提高心血管疾病與冠狀動脈心病風險。", [source(SOURCES["ms"], "反式脂肪酸會提高心血管疾病、冠狀動脈心病的風險。")]),
        rule("limit", "膽固醇", "Cholesterol", target("decrease", "mg/day", daily_limit="需依資料庫校正", note="與飽和脂肪限制合併判斷。"), level("high", ">=", None, "mg", "high_cholesterol"), ["動物內臟", "蛋黃", "魚卵", "蟹黃"], "膽固醇攝取需配合血脂管理，以降低動脈硬化風險。", [source(SOURCES["ms"], "動物內臟、蛋黃、魚卵、蟹黃等膽固醇含量高。")]),
        rule("recommend", "膳食纖維", "Dietary Fiber", target("increase", "g/day", daily_target="需依資料庫校正", note="以全穀、蔬菜、水果、豆類為主。"), level("rich", ">=", 3, "g", "high_fiber"), ["糙米", "燕麥", "五穀雜糧", "蔬菜", "水果", "豆類"], "膳食纖維有助血脂與體重控制，降低心血管代謝風險。", [source(SOURCES["ms"], "多吃高纖維質食物，纖維會減少血液中膽固醇。")]),
        rule("recommend", "不飽和脂肪", "Unsaturated Fat", target("replace", None, daily_target="需依資料庫校正", note="取代飽和脂肪與反式脂肪。"), level("source", ">=", None, "g", "unsaturated_fat_source"), ["橄欖油", "苦茶油", "葵花油", "大豆油", "堅果", "魚類"], "不飽和脂肪作為較佳油脂來源，有助降低心血管風險。", [source(SOURCES["ms"], "輪用植物油，以堅果種子類取代部分食用油。")]),
        rule("recommend", "Omega-3 脂肪酸", "Omega-3 Fatty Acids", target("increase", None, daily_target="需依資料庫校正", note="以深海魚、堅果與種子來源為主。"), level("source", ">=", None, "g", "omega_3_source"), ["鮭魚", "鯖魚", "秋刀魚", "核桃", "亞麻籽", "奇亞籽"], "Omega-3 脂肪酸有助抗發炎與血脂管理，可降低心血管風險。", [source(SOURCES["principle"], "高血脂患者適合吃富含 Omega-3 的深海魚與堅果。")]),
        rule("limit", "添加糖", "Added Sugar", target("decrease", "g/day", daily_limit="需依資料庫校正", note="含糖飲料與甜食需合併血糖與血脂風險評估。"), level("high", ">=", None, "g", "added_sugar_high"), ["含糖飲料", "甜點", "糕餅", "汽水", "可樂"], "添加糖會使血糖快速升高，也會造成血脂升高，增加心血管代謝風險。", [source(SOURCES["ms"], "含高糖甜點及含糖飲料易使血糖快速升高，也會造成血脂升高。")]),
    ],
    "chronic_kidney_disease": [
        rule("limit", "鈉", "Sodium", target("decrease", "mg/day", daily_limit="2000 mg/day 或需依醫囑校正", note="高血壓、水腫或腎功能下降者需特別限制。"), level("high", ">=", 600, "mg", "high_sodium"), ["鹽", "醬油", "胡椒鹽", "番茄醬", "辣椒醬", "豆瓣醬", "沙茶醬", "鹹魚", "泡菜", "加工食品"], "鈉攝取過多會造成水腫與血壓控制不佳，加重腎臟負擔。", [source(SOURCES["ckd"], "不要吃太鹹，烹調時減少鹽與醬油的使用量；過鹹會使血壓控制不佳。"), source(SOURCES["principle"], "慢性腎臟病避免醃製食品與高鈉食物，建議每日鈉低於 2000 毫克。")]),
        rule("limit", "蛋白質", "Protein", target("adjust_by_stage", "g/kg/day", daily_target="CKD 1-3: 0.8-1.0；CKD 3-4: 0.6-0.8；CKD 5 未透析: 0.3-0.6；透析: 1.2-1.5", note="需依分期、是否透析、糖尿病共病與營養狀態調整。"), level("high", ">=", None, "g", "high_protein"), ["紅肉", "大量魚肉", "乳製品", "豆類", "蛋", "肉類", "豆腐"], "腎功能下降時過量蛋白質會增加含氮廢物與腎臟負擔，但透析後需求可能上升。", [source(SOURCES["ckd"], "減少蛋白質食物攝取有助延緩腎功能下降；不同分期有不同蛋白質建議。"), source(SOURCES["principle"], "慢性腎臟病飲食建議因腎病分期不同而異，透析患者蛋白質攝取需提高。")]),
        rule("limit", "鉀", "Potassium", target("adjust_by_stage", "mg/day", daily_limit="2000-3000 mg/day 或依血鉀與尿量校正", note="尿量減少或高血鉀時需限制；不可套用高血壓的增鉀規則。"), level("high", ">=", None, "mg", "high_potassium"), ["番茄", "奇異果", "哈密瓜", "香瓜", "火龍果", "櫻桃", "草莓", "菜湯", "肉湯", "低鈉鹽", "薄鹽醬油"], "腎臟排鉀能力下降時，高鉀攝取可能造成高血鉀與心律不整。", [source(SOURCES["ckd"], "尿量減少時需減少高鉀食物，以免造成心律不整危害生命。"), source(SOURCES["principle"], "控制鉀攝取，預防高血鉀，建議每日 2000-3000 毫克。")]),
        rule("limit", "磷", "Phosphorus", target("decrease", "mg/day", daily_limit="低於 1000 mg/day 或依血磷校正", note="需依血磷、腎功能與藥物治療調整。"), level("high", ">=", None, "mg", "high_phosphorus"), ["奶類", "奶製品", "高磷食物", "加工食品"], "慢性腎臟病易有高磷血症，會影響骨骼、血管鈣化並損害腎功能。", [source(SOURCES["ckd"], "高磷食物會造成血磷異常，也會損害腎功能。"), source(SOURCES["principle"], "控制磷攝取，建議每日磷攝取量低於 1000 毫克。")]),
        rule("limit", "水分", "Fluid", target("adjust_by_stage", "mL/day", daily_limit="前一天尿量 + 500-700 mL；或依醫囑", note="僅在嚴重水腫、尿量減少或醫囑限水時套用。"), level("excess", None, None, "mL", "fluid_restriction_required"), ["水", "湯", "飲料", "菜湯", "肉湯"], "腎功能下降且尿量減少時，過量水分會造成水腫、低血鈉或心肺負擔。", [source(SOURCES["ckd"], "限制水份時，每日水份以前一天尿量再加上500~700毫升估計。"), source(SOURCES["principle"], "如有水腫、尿量減少，應遵醫囑限制水分攝取。")]),
        rule("recommend", "足夠熱量", "Energy", target("maintain", None, daily_target="需依體重、分期與營養狀態校正", note="低蛋白飲食時尤其需避免熱量不足。"), level("adequate", None, None, None, "energy_adequacy"), ["低氮澱粉", "玉米粉", "地瓜粉", "冬粉"], "低蛋白飲食若熱量不足，可能造成營養不良與蛋白質分解。", [source(SOURCES["ckd"], "低蛋白飲食時熱量一定要吃夠，營養才會好。"), source(SOURCES["principle"], "慢性腎臟病需攝取足夠熱量，避免營養不良。")]),
        rule("recommend", "高生物價蛋白質", "High Biological Value Protein", target("replace", None, daily_target="需依蛋白質總量限制校正", note="不是增加總蛋白，而是在蛋白質限量內優先選擇。"), level("preferred", None, None, None, "high_biological_value_protein"), ["蛋", "魚肉", "雞肉", "豆腐", "豆乾", "豆包"], "在蛋白質限量下優先選擇高生物價蛋白質，可維持營養並減少代謝廢物負擔。", [source(SOURCES["ckd"], "高品質蛋白質包括蛋、肉類與豆腐豆乾豆包等黃豆製品。"), source(SOURCES["principle"], "蛋白質來源選擇高生物價值，如雞蛋、魚肉、豆腐、雞肉。")]),
        rule("prohibit", "楊桃神經毒性成分", "Star Fruit Neurotoxic Compounds", target("avoid", None, daily_limit="避免", note="慢性腎臟病患者列為高風險避免項目。"), level("symptom_trigger", None, None, None, "star_fruit_or_extract"), ["楊桃", "楊桃汁"], "楊桃對慢性腎臟病患者具高風險，應避免食用。", [source(SOURCES["ckd"], "慢性腎臟病患者避免食用楊桃。")]),
    ],
    "stroke": [
        rule("limit", "鈉", "Sodium", target("decrease", "mg/day", daily_limit="需依資料庫校正", note="腦中風風險管理以血壓控制為核心。"), level("high", ">=", 600, "mg", "high_sodium"), ["鹽", "醬油", "醃製食品", "加工食品"], "控制鈉攝取有助血壓管理，降低腦血管風險。", [source(SOURCES["ms"], "代謝症候群增加心臟病及腦中風風險；健康飲食需低鹽。")]),
        rule("limit", "飽和脂肪", "Saturated Fat", target("decrease", "% energy", daily_limit="需依資料庫校正", note="降低血脂與動脈硬化風險。"), level("high", ">=", None, "g", "high_saturated_fat"), ["肥肉", "奶油", "動物油脂", "全脂奶"], "飽和脂肪會提高血脂與動脈硬化風險，與腦中風預防相關。", [source(SOURCES["ms"], "減少吃富含飽和脂肪酸及膽固醇的食物。")]),
        rule("prohibit", "反式脂肪", "Trans Fat", target("avoid", "g/day", daily_limit="越低越好", note="推薦系統視為高風險。"), level("contains", ">", 0, "g", "trans_fat_containing"), ["酥油", "硬乳瑪琳", "氫化油", "糕餅", "速食"], "反式脂肪會增加心血管與腦血管事件風險。", [source(SOURCES["ms"], "反式脂肪酸會提高心血管疾病、冠狀動脈心病的風險。")]),
        rule("recommend", "膳食纖維", "Dietary Fiber", target("increase", "g/day", daily_target="需依資料庫校正", note="以全穀、蔬菜、水果與豆類為主。"), level("rich", ">=", 3, "g", "high_fiber"), ["糙米", "燕麥", "蔬菜", "水果", "豆類"], "膳食纖維有助血脂、血糖與體重控制，降低腦中風相關代謝風險。", [source(SOURCES["ms"], "多吃高纖維質食物有助減少血液中膽固醇。")]),
        rule("recommend", "鉀", "Potassium", target("increase", None, daily_target="需排除腎功能不佳或高血鉀後校正", note="腎臟病或高血鉀者不可套用。"), level("rich", ">=", None, "mg", "high_potassium"), ["新鮮蔬果", "香蕉", "番茄", "菠菜"], "鉀攝取與血壓控制相關，可輔助降低腦血管風險。", [source(SOURCES["diet"], "新鮮蔬果多為高鉀食物，增加攝取可幫助血壓控制。")]),
        rule("recommend", "不飽和脂肪", "Unsaturated Fat", target("replace", None, daily_target="需依資料庫校正", note="取代飽和脂肪。"), level("source", ">=", None, "g", "unsaturated_fat_source"), ["橄欖油", "芥花油", "堅果", "魚類"], "不飽和脂肪可幫助心血管風險管理，間接降低腦中風風險。", [source(SOURCES["diet"], "炒菜多選用單元不飽和脂肪酸含量高的油脂。")]),
        rule("limit", "添加糖", "Added Sugar", target("decrease", "g/day", daily_limit="需依資料庫校正", note="合併糖尿病或代謝症候群時需加權。"), level("high", ">=", None, "g", "added_sugar_high"), ["含糖飲料", "甜點", "糕餅", "糖果"], "添加糖會惡化血糖與血脂，增加腦中風相關代謝風險。", [source(SOURCES["ms"], "高糖甜點與含糖飲料不利血糖控制，也會造成血脂升高。")]),
    ],
    "metabolic_syndrome": [
        rule("limit", "添加糖", "Added Sugar", target("decrease", "g/day", daily_limit="需依資料庫校正", note="高果糖飲料與甜點需優先限制。"), level("high", ">=", None, "g", "added_sugar_high"), ["市售茶飲", "包裝果汁", "汽水", "可樂", "精緻糕餅", "甜點"], "添加糖會使血糖快速升高並造成血脂升高，是代謝症候群三高風險因子。", [source(SOURCES["ms"], "含高糖的精緻糕餅與含糖飲料易使血糖快速升高，也會造成血脂升高。")]),
        rule("limit", "精製碳水化合物", "Refined Carbohydrate", target("decrease", None, daily_limit="需依資料庫校正", note="優先以全穀根莖類取代。"), level("high", ">=", None, "g", "refined_carbohydrate_high"), ["精緻糕餅", "甜點", "白飯", "甜麵包"], "精製碳水化合物會促進血糖與三酸甘油酯異常，不利胰島素阻抗。", [source(SOURCES["ms"], "代謝症候群與高糖、高油脂飲食相關；建議以全穀根莖類為主食。")]),
        rule("limit", "飽和脂肪", "Saturated Fat", target("decrease", "% energy", daily_limit="需依資料庫校正", note="低油飲食的一部分。"), level("high", ">=", None, "g", "high_saturated_fat"), ["肥肉", "動物皮", "椰子油", "棕櫚油", "奶油", "全脂奶"], "飽和脂肪會使血脂控制惡化並增加心血管風險。", [source(SOURCES["ms"], "減少吃富含飽和脂肪酸及膽固醇的食物。")]),
        rule("prohibit", "反式脂肪", "Trans Fat", target("avoid", "g/day", daily_limit="越低越好", note="推薦系統視為高風險。"), level("contains", ">", 0, "g", "trans_fat_containing"), ["酥油", "硬乳瑪琳", "氫化油", "酥脆食物", "糕餅類"], "反式脂肪會提高心血管疾病風險，代謝症候群者應強烈避免。", [source(SOURCES["ms"], "行動三：避免攝取反式脂肪酸。")]),
        rule("recommend", "膳食纖維", "Dietary Fiber", target("increase", "g/day", daily_target="需依資料庫校正", note="三低一高中的高纖。"), level("rich", ">=", 3, "g", "high_fiber"), ["糙米", "五穀雜糧", "燕麥", "薏仁", "地瓜", "山藥", "蔬菜", "水果", "菇類", "木耳", "海帶", "秋葵"], "高纖飲食有助血脂、血糖與體重控制，是代謝症候群飲食核心。", [source(SOURCES["ms"], "健康飲食運用三低一高：低油、低糖、低鹽、高纖。")]),
        rule("recommend", "不飽和脂肪", "Unsaturated Fat", target("replace", None, daily_target="需依資料庫校正", note="以好油取代動物油與反式脂肪。"), level("source", ">=", None, "g", "unsaturated_fat_source"), ["花生油", "苦茶油", "橄欖油", "葵花油", "大豆油", "腰果", "杏仁", "核桃", "花生"], "選用較佳油脂來源可改善心血管代謝風險。", [source(SOURCES["ms"], "選好的烹調方法及選用好油，輪用植物油，以堅果種子取代部分食用油。")]),
        rule("limit", "鈉", "Sodium", target("decrease", "mg/day", daily_limit="需依資料庫校正", note="三低一高中的低鹽。"), level("high", ">=", 600, "mg", "high_sodium"), ["鹽", "醬油", "醬料", "重口味食物", "加工食品", "麵線", "醃漬食物"], "低鹽飲食有助血壓控制，是代謝症候群三高管理之一。", [source(SOURCES["ms"], "切忌吃太鹹，減少鹽、醬油、各式醬料及重製或醃漬食物。")]),
        rule("limit", "酒精", "Alcohol", target("decrease", "alcohol equivalent/day", daily_limit="女性 <= 1；男性 <= 2", note="可依身體狀況適量或不喝酒。"), level("contains", ">", 0, "g", "alcohol_containing"), ["啤酒", "米酒", "紹興酒", "高粱酒", "葡萄酒", "威士忌"], "過量飲酒與代謝症候群及心血管風險相關，需限制。", [source(SOURCES["ms"], "減少或避免飲酒，女性每日不宜超過1個酒精當量，男性每日不宜超過2個酒精當量。")]),
    ],
    "gout": [
        rule("limit", "普林", "Purine", target("decrease", None, daily_limit="需依資料庫校正", note="急性發作期與高尿酸者需更嚴格限制。"), level("high", ">=", None, "mg", "high_purine"), ["內臟", "海鮮", "紅肉", "高嘌呤食物"], "高普林食物會增加尿酸生成，誘發或惡化痛風。", [source(SOURCES["principle"], "痛風限制攝取高嘌呤食物，如內臟、海鮮、紅肉。")]),
        rule("prohibit", "酒精", "Alcohol", target("avoid", None, daily_limit="避免或依醫囑限制", note="啤酒對痛風尤其高風險。"), level("contains", ">", 0, "g", "alcohol_containing"), ["啤酒", "酒精飲品"], "酒精會影響尿酸代謝，啤酒尤其容易增加痛風風險。", [source(SOURCES["principle"], "痛風建議少吃酒精，尤其是啤酒。")]),
        rule("limit", "果糖", "Fructose", target("decrease", "g/day", daily_limit="需依資料庫校正", note="含糖飲料與高果糖產品需限制。"), level("high", ">=", None, "g", "fructose_high"), ["含糖飲料", "果糖飲料", "高糖甜品"], "果糖代謝會促進尿酸生成，不利尿酸控制。", [source(SOURCES["ms"], "添加高果糖糖的市售茶飲、包裝飲料、可樂、汽水需避免。"), source(SOURCES["principle"], "痛風與高尿酸血症需控制尿酸相關飲食風險。")]),
        rule("recommend", "水", "Water", target("increase", "L/day", daily_target=">= 2 L/day；需依心腎功能校正", note="心衰竭或腎臟病限水者不可直接套用。"), level("adequate", None, None, "mL", "hydration"), ["白開水", "無糖飲用水"], "足夠水分有助尿酸排泄並降低尿酸濃縮風險。", [source(SOURCES["principle"], "痛風建議多喝水（2L以上）。")]),
        rule("limit", "內臟來源普林", "Organ Meat Purine", target("decrease", None, daily_limit="需依資料庫校正", note="此為普林的高風險食物子類，用於推薦系統細分判斷。"), level("high", ">=", None, "mg", "organ_meat_purine"), ["動物內臟", "肝臟", "腎臟"], "內臟通常為高普林來源，痛風者需優先限制。", [source(SOURCES["principle"], "痛風建議少吃內臟。")]),
    ],
    "hyperuricemia": [
        rule("limit", "普林", "Purine", target("decrease", None, daily_limit="需依資料庫校正", note="目標為預防尿酸升高與痛風發作。"), level("high", ">=", None, "mg", "high_purine"), ["內臟", "海鮮", "紅肉", "高嘌呤食物"], "高普林食物會提高尿酸生成，增加高尿酸血症與痛風風險。", [source(SOURCES["principle"], "痛風（高尿酸血症）限制攝取高嘌呤食物。"), source(SOURCES["ckd"], "高尿酸血症可能引起腎臟功能損害。")]),
        rule("limit", "酒精", "Alcohol", target("decrease", None, daily_limit="需依資料庫校正；啤酒優先避免", note="若已痛風發作可升級為 prohibit。"), level("contains", ">", 0, "g", "alcohol_containing"), ["啤酒", "酒精飲品"], "酒精會影響尿酸代謝並提高痛風發作風險。", [source(SOURCES["principle"], "痛風建議少吃酒精，尤其是啤酒。")]),
        rule("limit", "果糖", "Fructose", target("decrease", "g/day", daily_limit="需依資料庫校正", note="含糖飲料與高果糖產品需限制。"), level("high", ">=", None, "g", "fructose_high"), ["市售茶飲", "包裝果汁", "汽水", "可樂", "含糖飲料"], "果糖攝取過多會促進尿酸生成，不利高尿酸血症控制。", [source(SOURCES["ms"], "避免添加高果糖糖的市售茶飲、包裝飲料、可樂、汽水。")]),
        rule("recommend", "水", "Water", target("increase", "L/day", daily_target=">= 2 L/day；需依心腎功能校正", note="若合併腎臟病或限水醫囑需調整。"), level("adequate", None, None, "mL", "hydration"), ["白開水", "無糖飲用水"], "足夠水分有助尿酸排泄並降低尿酸濃縮。", [source(SOURCES["principle"], "痛風建議多喝水（2L以上）。")]),
    ],
    "gastroesophageal_reflux_disease": [
        rule("limit", "脂肪", "Fat", target("decrease", None, daily_limit="需依資料庫校正", note="高脂食物可能延緩胃排空並誘發症狀。"), level("high", ">=", None, "g", "high_fat_or_symptom_trigger"), ["油炸食物", "高脂食物", "低脂易消化食物的反向條件"], "高脂飲食可能加重胃食道逆流，文件建議多吃低脂易消化食物。", [source(SOURCES["principle"], "胃食道逆流飲食調理建議：多吃低脂、易消化食物。")]),
        rule("limit", "咖啡因", "Caffeine", target("decrease", None, daily_limit="依症狀觸發反應調整", note="可用 symptom_trigger 規則判斷。"), level("symptom_trigger", None, None, None, "caffeine_trigger"), ["咖啡", "茶", "含咖啡因飲品"], "咖啡因可能誘發胃酸逆流或胸口灼熱症狀。", [source(SOURCES["principle"], "胃食道逆流避免酸性食物，如柑橘類、番茄、咖啡。")]),
        rule("limit", "酒精", "Alcohol", target("decrease", None, daily_limit="依症狀與醫囑調整", note="若明顯誘發症狀可升級為 prohibit。"), level("symptom_trigger", None, None, None, "alcohol_trigger"), ["酒類", "啤酒", "葡萄酒", "烈酒"], "酒精可能降低下食道括約肌張力並誘發逆流症狀。", [source(SOURCES["principle"], "胃食道逆流屬腸胃疾病，飲食重點為易消化、低刺激。")]),
        rule("limit", "辛辣刺激成分", "Spicy Compounds", target("decrease", None, daily_limit="依症狀觸發反應調整", note="個體差異大，推薦系統以 symptom_trigger 判斷。"), level("symptom_trigger", None, None, None, "spicy_trigger"), ["辣椒", "辣椒醬", "辛辣食物"], "辛辣刺激成分可能誘發胃食道逆流症狀，需依個人反應限制。", [source(SOURCES["principle"], "腸胃疾病飲食調理重點為易消化、低刺激。")]),
        rule("limit", "酸性食物成分", "Acidic Food Components", target("decrease", None, daily_limit="依症狀觸發反應調整", note="可用 symptom_trigger 規則判斷。"), level("symptom_trigger", None, None, None, "acidic_food_trigger"), ["柑橘類", "番茄", "酸性食物"], "酸性食物可能刺激食道與胃部症狀，胃食道逆流者需限制。", [source(SOURCES["principle"], "胃食道逆流避免酸性食物，如柑橘類、番茄、咖啡。")]),
        rule("limit", "碳酸飲料", "Carbonated Drinks", target("decrease", None, daily_limit="依症狀觸發反應調整", note="可用 symptom_trigger 規則判斷。"), level("symptom_trigger", None, None, None, "carbonated_drink_trigger"), ["汽水", "可樂", "碳酸飲料"], "碳酸飲料可能增加胃內壓力並誘發逆流症狀。", [source(SOURCES["diet"], "高血壓飲食原則列出碳酸飲料屬加工高鈉或需少用食品；胃食道逆流則依症狀觸發管理。")]),
    ],
}


def build_disease_payload():
    diseases = []
    for disease_id, name_en, name_zh in DISEASE_ROWS:
        risk_notes = list(COMMON_RISK_NOTES)
        if disease_id == "chronic_kidney_disease":
            risk_notes.append("慢性腎臟病飲食限制會依分期、是否透析、血鉀、血磷、水腫與尿量不同而改變，不可用單一規則套用所有人。")
            risk_notes.append("若同時有高血壓規則建議增加鉀，慢性腎臟病或高血鉀規則應優先覆蓋。")
        if disease_id in {"gout", "hyperuricemia"}:
            risk_notes.append("若同時有慢性腎臟病、心衰竭或醫囑限水，增加水分規則需重新加權。")
        if disease_id == "gastroesophageal_reflux_disease":
            risk_notes.append("胃食道逆流常有個人化症狀觸發差異，food_level_rule 可用 symptom_trigger 作為推薦系統條件。")

        diseases.append(
            {
                "disease_id": disease_id,
                "disease_name_zh": name_zh,
                "disease_name_en": name_en,
                "disease_nutrient_relations": RULES_BY_DISEASE[disease_id],
                "diet_pattern": DIET_PATTERNS[disease_id],
                "risk_notes": risk_notes,
            }
        )
    return {
        "metadata": {
            "dataset_name": "chronic_disease_nutrient_rules",
            "version": "1.0",
            "language": "zh-TW",
            "description": "慢性疾病與營養成分之間的飲食規則，用於 Knowledge Graph 與 Recommendation System",
            "relation_types": RELATION_TYPES,
            "source_corpus": sorted(set(SOURCES.values())),
            "rag_method": {
                "retrieval_unit": "section_or_rule_chunk",
                "normalization": "Disease-Food evidence is converted to Disease-Nutrient relations; foods remain in example_foods.",
                "evidence_field": "Each relation keeps source file and source evidence snippets in sources.",
            },
        },
        "diseases": diseases,
    }


def slugify_nutrient(name_en):
    return name_en.lower().replace(" ", "_").replace("-", "_")


def build_nutrient_index(payload):
    index = {}
    for disease in payload["diseases"]:
        for relation in disease["disease_nutrient_relations"]:
            nutrient_id = slugify_nutrient(relation["nutrient_name_en"])
            if nutrient_id not in index:
                index[nutrient_id] = {
                    "nutrient_id": nutrient_id,
                    "nutrient_name_zh": relation["nutrient_name_zh"],
                    "nutrient_name_en": relation["nutrient_name_en"],
                    "related_diseases": [],
                    "example_foods": [],
                    "food_level_rules": [],
                }
            index[nutrient_id]["related_diseases"].append(
                {
                    "disease_id": disease["disease_id"],
                    "disease_name_zh": disease["disease_name_zh"],
                    "disease_name_en": disease["disease_name_en"],
                    "relation": relation["relation"],
                    "reason": relation["reason"],
                }
            )
            index[nutrient_id]["example_foods"].extend(relation["example_foods"])
            index[nutrient_id]["food_level_rules"].append(
                {
                    "disease_id": disease["disease_id"],
                    "relation": relation["relation"],
                    "food_level_rule": relation["food_level_rule"],
                }
            )

    for item in index.values():
        item["example_foods"] = sorted(set(item["example_foods"]))
        seen = set()
        deduped = []
        for related in item["related_diseases"]:
            key = (related["disease_id"], related["relation"])
            if key not in seen:
                deduped.append(related)
                seen.add(key)
        item["related_diseases"] = deduped

    return {
        "metadata": {
            "dataset_name": "chronic_disease_nutrient_index",
            "version": "1.0",
            "language": "zh-TW",
            "description": "慢性疾病飲食規則中使用到的營養成分索引，可由營養成分反查相關疾病與規則。",
        },
        "nutrients": sorted(index.values(), key=lambda item: item["nutrient_id"]),
    }


def validate_no_duplicate_relations(payload):
    errors = []
    for disease in payload["diseases"]:
        seen = defaultdict(int)
        for relation in disease["disease_nutrient_relations"]:
            key = (relation["relation"], relation["nutrient_name_en"])
            seen[key] += 1
        for key, count in seen.items():
            if count > 1:
                errors.append(f"{disease['disease_id']} duplicated relation: {key}")
    return errors


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    payload = build_disease_payload()
    duplicate_errors = validate_no_duplicate_relations(payload)
    if duplicate_errors:
        raise ValueError("\n".join(duplicate_errors))

    nutrient_index = build_nutrient_index(payload)
    RULES_OUTPUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    NUTRIENT_INDEX_OUTPUT_PATH.write_text(json.dumps(nutrient_index, ensure_ascii=False, indent=2), encoding="utf-8")
    print(RULES_OUTPUT_PATH)
    print(NUTRIENT_INDEX_OUTPUT_PATH)


if __name__ == "__main__":
    main()
