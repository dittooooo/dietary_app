from fractions import Fraction

from bs4 import BeautifulSoup
import requests, re
import util


def scrape_icook_recipe(url, recipe_id):
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
    }
    res = requests.get(url, headers=headers)

    soup = BeautifulSoup(res.text, 'html.parser')
    recipe_name = soup.find(id = "recipe-name")
    if(recipe_name is None):
        return None

    recipe = {
        "recipe_id" : recipe_id,
        "name" : recipe_name.string.strip(),
        "servings" : soup.select_one(".servings span").string.strip()
    }

    ingredients = []
    ingredient_name = soup.find_all(class_ = "ingredient-search")
    ingredient_amount = soup.find_all(class_ = "ingredient-unit")
    
    for i in range(len(ingredient_name)): 
        name = ingredient_name[i].string.strip()
        amount = ingredient_amount[i].string.strip()
        
        ingredients.append(parse_ingredient(name, amount))

    recipe["ingredients"] = ingredients

    return recipe

# 解析食材名稱與份量
def parse_ingredient(ingredient_str, amount_str):
    ingredient = {
        "name_raw": ingredient_str,
        "name": ingredient_name_parse(ingredient_str),
        "amount_raw": amount_str,
        "amount_value": None,
        "amount_unit": None,
        "amount_note": None
    }

    parsed_amount = ingredient_amount_parse(amount_str)
    ingredient["amount_value"] = parsed_amount["amount_value"]
    ingredient["amount_unit"] = parsed_amount["amount_unit"]
    ingredient["amount_note"] = parsed_amount["amount_note"]

    return ingredient
# 解析食材名稱，去除形容詞、括號等
def ingredient_name_parse(name_str):
    if name_str is None:
        return None
    
    adj_keywords = ["碎", "末", "絲", "片", "塊", "丁", "條", "段", "片", "切片", "切丁", "切絲"]

    for keyword in adj_keywords:
        if name_str.find(keyword) != -1:
            name_str = name_str.replace(keyword, "")

    name_str = re.sub(r'\s.*', '', name_str)
    name_str = re.sub(r'\(.*?\)', '', name_str)
    return name_str.strip()

# 解析食材份量
def ingredient_amount_parse(amount_str):
    result = {
        "amount_value" : None,
        "amount_unit" : None,
        "amount_note" : None
    }

    if not amount_str:
        return result
    
    note_kewords = ["少許", "適量", "依喜好", "適量即可", "酌量", "隨意"]
    approx_keywords = ["約", "大約", "約略", "大概"]

    # 模糊份量
    if amount_str in note_kewords:
        result["amount_note"] = amount_str
        return result

    # 大概份量
    for approx in approx_keywords:
        if amount_str.startswith(approx):
            result["amount_note"] = approx
            amount_str = amount_str[len(approx):].strip()
            break
    
    # Range: 2-3杯, 1~2匙, 1.5-3克
    amount_match = re.match(r'^(\d+(?:\.\d+)?)[\-~](\d+(?:\.\d+)?)(.*)$', amount_str)
    if amount_match:
        result["amount_value"] = (float(amount_match.group(1)) + float(amount_match.group(2))) / 2
        result["amount_unit"] = util.normalize_unit(amount_match.group(3).strip())
        return result
    
    # Range: 分數
    amount_match = re.match(r'^(\d+/\d+)(.*)$', amount_str)
    if(amount_match):
        frac_str = amount_match.group(1)
        result["amount_value"] = float(Fraction(frac_str))
        result["amount_unit"] = util.normalize_unit(amount_match.group(2).strip())
        return result
    
    # Range: 整數, 小數
    amount_match = re.match(r'^(\d+(?:\.+\d+)?)(.*)$', amount_str)
    if amount_match:
        result["amount_value"] = float(amount_match.group(1))
        result["amount_unit"] = util.normalize_unit(amount_match.group(2).strip())
        return result

    amount_match = re.match(r'^(半)(.*)$', amount_str)
    if amount_match:
        result["amount_value"] = 0.5
        result["amount_unit"] = util.normalize_unit(amount_match.group(2).strip())
        return result
    
    result["amount_note"] = amount_str.strip()
    return result

