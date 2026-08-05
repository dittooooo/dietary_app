from fractions import Fraction
from bs4 import BeautifulSoup
import requests, re
import utility


def scrape_icook_recipe(url, recipe_id):
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"
    }
    res = requests.get(url, headers=headers, timeout=10)

    soup = BeautifulSoup(res.text, "html.parser")
    recipe_name = soup.find(id="recipe-name")
    servings = soup.select_one(".servings span")
    recipe_name_text = clean_recipe_name(_node_text(recipe_name))
    servings_text = _node_text(servings)

    if recipe_name_text is None or servings_text is None:
        return None

    recipe = {
        "recipe_id": "r" + str(recipe_id),
        "name": recipe_name_text,
        "servings": servings_text,
        "ingredients": []
    }

    recipe["ingredients"] = parse_ingredients(soup)

    return recipe



def _node_text(node):
    if node is None:
        return None
    return node.get_text(strip=True)


def clean_recipe_name(name):
    if name is None:
        return None

    emoji_pattern = re.compile(
        r"[\U0001F300-\U0001F5FF"
        r"\U0001F600-\U0001F64F"
        r"\U0001F680-\U0001F6FF"
        r"\U0001F900-\U0001F9FF"
        r"\U0001FA70-\U0001FAFF"
        r"\u2600-\u26FF"
        r"\u2700-\u27BF]+",
        flags=re.UNICODE
    )

    cleaned_name = emoji_pattern.sub("", name)
    cleaned_name = re.sub(r"\([^)]*\)", "", cleaned_name)
    cleaned_name = re.sub(r"\[[^\]]*\]", "", cleaned_name)
    cleaned_name = re.sub("\uFF08[^\uFF09]*\uFF09", "", cleaned_name)
    cleaned_name = re.sub(r"\s+", " ", cleaned_name)
    return cleaned_name.strip()



def parse_ingredients(soup):
    ingredients = []
    ingredient_names = soup.select(".ingredient-search")
    ingredient_amounts = soup.select(".ingredient-unit")

    for ingredient_name_node, ingredient_amount_node in zip(ingredient_names, ingredient_amounts):
        name = _node_text(ingredient_name_node)
        amount = _node_text(ingredient_amount_node)

        if not name:
            continue

# 解析食材名稱與份量
        if amount is None:
            amount = ""

        ingredient = {
            "name_raw": name,
            "name": ingredient_name_parse(name),
            "amount_raw": amount,
            "amount_value": None,
            "amount_unit": None,
            "amount_note": None
        }

        parsed_amount = ingredient_amount_parse(amount)
        ingredient["amount_value"] = parsed_amount["amount_value"]
        ingredient["amount_unit"] = parsed_amount["amount_unit"]
        ingredient["amount_note"] = parsed_amount["amount_note"]

        ingredients.append(ingredient)

    return ingredients


# 解析食材名稱，去除形容詞、括號等
def ingredient_name_parse(name_str):
    if name_str is None:
        return None

    for keyword in utility.INGREDIENT_NAME_ADJ_KEYWORDS:
        if name_str.find(keyword) != -1:
            name_str = name_str.replace(keyword, "")

    name_str = re.sub(r"\s.*", "", name_str)
    name_str = re.sub(r"\(.*?\)", "", name_str)
    return name_str.strip()

# 解析食材份量

def ingredient_amount_parse(amount_str):
    result = {
        "amount_value": None,
        "amount_unit": None,
        "amount_note": None
    }

    if not amount_str:
        return result

    # 模糊份量
    if amount_str in utility.AMOUNT_KEYWORDS:
        result["amount_note"] = amount_str
        return result

    # 大概份量
    for approx in utility.AMOUNT_APPROX_KEYWORDS:
        if amount_str.startswith(approx):
            result["amount_note"] = approx
            amount_str = amount_str[len(approx):].strip()
            break
    # Range: 2-3杯, 1~2匙, 1.5-3克

    match_range = re.match(r"^(\d+(?:\.\d+)?)[\-~](\d+(?:\.\d+)?)(.*)$", amount_str)
    if match_range:
        result["amount_value"] = (float(match_range.group(1)) + float(match_range.group(2))) / 2
        result["amount_unit"] = utility.normalize_unit(match_range.group(3).strip())
        return result
    
    # Range: 分數

    match_fraction = re.match(r"^(\d+/\d+)(.*)$", amount_str)
    if match_fraction:
        frac_str = match_fraction.group(1)
        result["amount_value"] = float(Fraction(frac_str))
        result["amount_unit"] = utility.normalize_unit(match_fraction.group(2).strip())
        return result
    # Range: 整數, 小數

    match_number = re.match(r"^(\d+(?:\.\d+)?)(.*)$", amount_str)
    if match_number:
        result["amount_value"] = float(match_number.group(1))
        result["amount_unit"] = utility.normalize_unit(match_number.group(2).strip())
        return result

    match_half = re.match("^" + "\u534A" + r"(.*)$", amount_str)
    if match_half:
        result["amount_value"] = 0.5
        result["amount_unit"] = utility.normalize_unit(match_half.group(1).strip())
        return result

    result["amount_note"] = amount_str.strip()
    return result
