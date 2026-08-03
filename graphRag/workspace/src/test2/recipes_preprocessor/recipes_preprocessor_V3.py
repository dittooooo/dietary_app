"""
recipes_preprocessor.py - V3

版本變更紀錄（changelog）：
V1
- 建立 recipes.json 前處理基本概念
- 支援將 amount_value 除以 servings，換算為 1 人份
- 提出 rule-based + unit lookup + LLM fallback 的整體流程

V2
- 實作完整前處理程式
- 支援讀取 recipes.json 並輸出 recipes_per_serving_v2.json
- 將食材數量標準化為 1 人份
- 優先用規則、通用單位表、食材單位表轉成 gram_per_serving
- 對無法穩定換算者標記 needs_llm = true
- 自動生成 llm_prompt，方便後續接 LLM API
- 保留 amount_raw / amount_note / gram_source 等欄位，方便追蹤來源

V3
- 正式加入 LLM 估重流程
- 支援 dry-run 模式：只輸出待估項目，不呼叫 API
- 支援 llm mode：對 needs_llm = true 的食材呼叫 LLM，回填估計克數
- 新增 llm_confidence / llm_reason / llm_model 欄位
- 僅對 unresolved 或 note 型食材使用 LLM，避免不必要成本
- 支援限制只測試前 N 道食譜，方便小量驗證
"""

import json
import os
import re
from fractions import Fraction
from typing import Any, Dict, List, Optional, Tuple

# =========================================================
# 一、食材與單位換算表
# =========================================================

INGREDIENT_UNIT_TO_GRAM = {
    "蒜蓉": {
        "大匙": 12.0,
        "小匙": 4.0,
    },
    "蒜頭": {
        "瓣": 5.0,
        "顆": 5.0,
        "粒": 5.0,
        "小個": 4.0,
    },
    "洋蔥": {
        "顆": 150.0,
        "個": 150.0,
    },
    "紫色洋蔥": {
        "顆": 120.0,
        "個": 120.0,
    },
    "辣椒": {
        "根": 12.0,
        "個": 12.0,
    },
    "朝天椒": {
        "根": 5.0,
        "個": 5.0,
    },
    "青蔥": {
        "根": 15.0,
        "株": 15.0,
    },
    "薑": {
        "片": 3.0,
        "薄片": 2.0,
    },
    "老薑": {
        "片": 3.0,
    },
    "白蝦": {
        "隻": 18.0,
    },
    "蝦仁": {
        "隻": 8.0,
    },
    "雞蛋": {
        "顆": 50.0,
        "": 50.0,
    },
    "水煮蛋": {
        "顆": 50.0,
        "": 50.0,
    },
    "豆腐": {
        "盒": 300.0,
    },
    "嫩豆腐": {
        "盒": 300.0,
    },
    "瘦豬絞肉": {
        "盒": 300.0,
    },
    "玉米罐頭": {
        "罐": 340.0,
    },
    "蕃茄糊": {
        "罐": 400.0,
    },
    "金沙豆腐醬": {
        "包": 100.0,
    },
    "滷味包": {
        "包": 20.0,
    },
    "苦瓜": {
        "條": 300.0,
        "根": 300.0,
    },
    "牛肋條": {
        "條": 250.0,
    },
    "貢丸": {
        "顆": 25.0,
    },
    "雞腿排": {
        "排": 180.0,
    },
    "免煮麵皮": {
        "片": 10.0,
    },
    "關廟麵": {
        "片": 25.0,
    },
    "鱸魚": {
        "片": 125.0,
    },
}

GENERAL_UNIT_TO_GRAM = {
    "大匙": 15.0,
    "湯匙": 15.0,
    "小匙": 5.0,
    "茶匙": 5.0,
    "毫升": 1.0,
    "ml": 1.0,
    "克": 1.0,
    "公克": 1.0,
    "g": 1.0,
    "斤": 600.0,
    "碗": 240.0,
    "飯碗": 240.0,
    "米杯": 180.0,
}

INGREDIENT_DENSITY_OVERRIDE = {
    "醬油": {
        "大匙": 15.0,
        "湯匙": 15.0,
        "小匙": 5.0,
        "飯碗": 240.0,
    },
    "砂糖": {
        "大匙": 12.5,
        "小匙": 4.2,
        "飯碗": 180.0,
    },
    "冰糖": {
        "大匙": 12.0,
        "小匙": 4.0,
    },
    "油": {
        "大匙": 13.5,
        "小匙": 4.5,
    },
    "橄欖油": {
        "大匙": 13.5,
        "小匙": 4.5,
    },
    "麻油": {
        "大匙": 13.5,
        "小匙": 4.5,
    },
    "牛奶": {
        "毫升": 1.03,
    },
    "紅酒": {
        "毫升": 0.99,
    },
    "水": {
        "毫升": 1.0,
        "碗": 240.0,
        "飯碗": 240.0,
        "米杯": 180.0,
    },
}

# =========================================================
# 二、基本參數
# =========================================================

INPUT_PATH = r"workspace\src\test2\data\input\recipes.json"
OUTPUT_PATH = r"workspace\src\test2\data\output\recipes_per_serving_v3.json"
LLM_CANDIDATES_OUTPUT_PATH = r"workspace\src\test2\data\output\recipes_llm_candidates_v3.json"

# 模式：
# - "dry_run": 不呼叫 API，只輸出待估項目
# - "llm": 真正呼叫 API
MODE = "llm"

# 可只測試前 N 道。None 表示全部
TEST_LIMIT = 10

# OpenAI 參數
# NOTE: 這裡放的是「環境變數名稱」，不是 API key 本身。
# 請在環境變數中設定 OPENAI_API_KEY，而不要把 key 寫進程式碼/版本庫。
try:
    from dotenv import load_dotenv  # type: ignore

    load_dotenv()
except Exception:
    pass

# NOTE: 這裡放的是「環境變數名稱」，不是 API key 本身。
OPENAI_API_KEY_ENV = "OPENAI_API_KEY"
OPENAI_MODEL = "gpt-4.1"

# =========================================================
# 三、工具函式
# =========================================================

def safe_float(x: Any) -> Optional[float]:
    if x is None:
        return None
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def round_smart(x: Optional[float], digits: int = 2) -> Optional[float]:
    if x is None:
        return None
    return round(x, digits)


def normalize_unit(unit: Optional[str]) -> Optional[str]:
    if unit is None:
        return None
    unit = unit.strip()
    mapping = {
        "公克": "克",
        "g": "克",
        "ml": "毫升",
        "湯匙": "大匙",
        "茶匙": "小匙",
        "辨": "瓣",
    }
    return mapping.get(unit, unit)


def normalize_name(name: Optional[str]) -> Optional[str]:
    if not name:
        return name
    name = name.strip()
    alias = {
        "蒜": "蒜頭",
        "大蒜": "蒜頭",
        "蒜末": "蒜頭",
        "薑片": "薑",
        "老薑片": "老薑",
        "米酒水": "米酒",
        "開水": "水",
        "清水": "水",
        "植物油": "油",
        "食用油": "油",
        "醬油露": "醬油",
    }
    return alias.get(name, name)


def fraction_to_float(text: str) -> Optional[float]:
    try:
        return float(Fraction(text))
    except Exception:
        return None


def try_parse_amount_from_raw(amount_raw: Optional[str]) -> Optional[float]:
    if not amount_raw:
        return None

    raw = amount_raw.strip()

    zh_map = {
        "半": 0.5,
        "半顆": 0.5,
        "半個": 0.5,
        "半根": 0.5,
        "半條": 0.5,
        "半包": 0.5,
        "半盒": 0.5,
        "半飯碗": 0.5,
        "三分之一": 1 / 3,
        "三分之一根": 1 / 3,
        "四分之一": 0.25,
        "1/2": 0.5,
        "1／2": 0.5,
        "1/3": 1 / 3,
        "1／3": 1 / 3,
        "1/4": 0.25,
        "1／4": 0.25,
    }

    if raw in zh_map:
        return zh_map[raw]

    for key, value in zh_map.items():
        if raw.startswith(key):
            return value

    frac = fraction_to_float(raw)
    if frac is not None:
        return frac

    match = re.match(r"^\d+(\.\d+)?$", raw)
    if match:
        return float(raw)

    return None


def get_servings(recipe: Dict[str, Any]) -> float:
    servings = safe_float(recipe.get("servings"))
    if servings is None or servings <= 0:
        raise ValueError(f"Invalid servings in recipe_id={recipe.get('recipe_id')}")
    return servings


# =========================================================
# 四、規則轉克邏輯
# =========================================================

def convert_to_grams(
    ingredient_name: str,
    amount_value: Optional[float],
    amount_unit: Optional[str],
) -> Tuple[Optional[float], str]:
    if amount_value is None:
        return None, "unresolved"

    name = normalize_name(ingredient_name)
    unit = normalize_unit(amount_unit)

    if unit == "克":
        return amount_value, "direct_gram"

    if unit == "毫升":
        density = INGREDIENT_DENSITY_OVERRIDE.get(name, {}).get("毫升", 1.0)
        return amount_value * density, "ml_to_g"

    if name in INGREDIENT_UNIT_TO_GRAM and unit in INGREDIENT_UNIT_TO_GRAM[name]:
        return amount_value * INGREDIENT_UNIT_TO_GRAM[name][unit], "unit_lookup"

    if name in INGREDIENT_DENSITY_OVERRIDE and unit in INGREDIENT_DENSITY_OVERRIDE[name]:
        return amount_value * INGREDIENT_DENSITY_OVERRIDE[name][unit], "density_override"

    if unit in GENERAL_UNIT_TO_GRAM:
        return amount_value * GENERAL_UNIT_TO_GRAM[unit], "general_unit_lookup"

    return None, "unresolved"


def needs_llm_estimate(
    ingredient: Dict[str, Any],
    gram_per_serving: Optional[float],
    gram_source: str,
) -> bool:
    note = ingredient.get("amount_note")
    unit = normalize_unit(ingredient.get("amount_unit"))

    if note in {"適量", "可有可無"}:
        return True

    if gram_per_serving is None:
        return True

    ambiguous_units = {
        "包", "盒", "份", "碗", "飯碗",
        "個", "顆", "根", "條", "片", "株", "朵", "罐"
    }

    if unit in ambiguous_units and gram_source in {"general_unit_lookup", "unresolved"}:
        return True

    return False


# =========================================================
# 五、LLM Prompt
# =========================================================

def build_llm_prompt(recipe_name: str, servings: float, ingredient: Dict[str, Any]) -> str:
    name = normalize_name(ingredient.get("name"))
    amount_raw = ingredient.get("amount_raw")
    amount_value = safe_float(ingredient.get("amount_value"))
    amount_unit = normalize_unit(ingredient.get("amount_unit"))
    amount_note = ingredient.get("amount_note")

    per_serving_value = None
    if amount_value is not None and servings > 0:
        per_serving_value = amount_value / servings

    return f"""
你是料理食材重量估算助手。請估計下列食材在「1人份」時，大約等於多少公克。

要求：
1. 請根據台灣常見家庭料理習慣估算。
2. 若是調味料，請依一般料理密度估算。
3. 若資訊不足，仍請給出最合理的近似值。
4. estimated_grams 必須是數字。
5. 回傳 JSON，不要附加其他文字。

JSON 格式：
{{
  "ingredient_name": "...",
  "recipe_name": "...",
  "per_serving_original_text": "...",
  "estimated_grams": 0.0,
  "confidence": "high|medium|low",
  "reason": "..."
}}

資料：
- recipe_name: {recipe_name}
- recipe_servings: {servings}
- ingredient_name: {name}
- ingredient_amount_raw: {amount_raw}
- ingredient_amount_value: {amount_value}
- ingredient_amount_unit: {amount_unit}
- ingredient_amount_note: {amount_note}
- per_serving_value: {per_serving_value}
- per_serving_unit: {amount_unit}
""".strip()


# =========================================================
# 六、LLM 呼叫
# =========================================================

def estimate_with_llm(prompt: str) -> Dict[str, Any]:
    """
    這裡使用 OpenAI Python SDK。
    安裝：
        pip install openai

    環境變數：
        export OPENAI_API_KEY="your_key"
    """
    if OPENAI_API_KEY_ENV.startswith("sk-"):
        raise RuntimeError(
            "OPENAI_API_KEY_ENV 應為環境變數名稱（例如 'OPENAI_API_KEY'），不要把 API key 直接寫在程式碼中。"
        )
    api_key = os.getenv(OPENAI_API_KEY_ENV)
    if not api_key:
        raise RuntimeError(
            f"環境變數 {OPENAI_API_KEY_ENV} 未設定，無法呼叫 LLM。"
        )

    try:
        from openai import OpenAI
    except ImportError as e:
        raise RuntimeError(
            "未安裝 openai 套件。請先執行：pip install openai"
        ) from e

    client = OpenAI(api_key=api_key)

    response = client.responses.create(
        model=OPENAI_MODEL,
        input=prompt,
    )

    text = response.output_text.strip()
    data = extract_json_object(text)

    estimated_grams = safe_float(data.get("estimated_grams"))
    if estimated_grams is None:
        raise ValueError(f"LLM 回傳 estimated_grams 無法解析: {text}")

    return {
        "estimated_grams": estimated_grams,
        "confidence": data.get("confidence"),
        "reason": data.get("reason"),
        "model": OPENAI_MODEL,
        "raw_response": text,
    }


def extract_json_object(text: str) -> Dict[str, Any]:
    """
    容忍 LLM 在 JSON 外加文字；抓取第一個完整 JSON object。
    """
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise ValueError(f"無法從 LLM 回應中擷取 JSON: {text}")

    json_str = text[start:end + 1]
    return json.loads(json_str)


# =========================================================
# 七、前處理主流程
# =========================================================

def preprocess_ingredient(
    ingredient: Dict[str, Any],
    servings: float,
    recipe_name: str,
    mode: str,
) -> Dict[str, Any]:
    ing_name = normalize_name(ingredient.get("name"))
    amount_value = safe_float(ingredient.get("amount_value"))
    amount_unit = normalize_unit(ingredient.get("amount_unit"))
    amount_raw = ingredient.get("amount_raw")
    amount_note = ingredient.get("amount_note")

    if amount_value is None:
        parsed = try_parse_amount_from_raw(amount_raw)
        if parsed is not None:
            amount_value = parsed

    per_serving_value = None
    if amount_value is not None:
        per_serving_value = amount_value / servings

    gram_per_serving, gram_source = convert_to_grams(
        ingredient_name=ing_name,
        amount_value=per_serving_value,
        amount_unit=amount_unit,
    )

    llm_needed = needs_llm_estimate(
        ingredient=ingredient,
        gram_per_serving=gram_per_serving,
        gram_source=gram_source,
    )

    result = {
        "name_raw": ingredient.get("name_raw"),
        "name": ing_name,
        "amount_raw": amount_raw,
        "amount_value": amount_value,
        "amount_unit": amount_unit,
        "amount_note": amount_note,

        "amount_per_serving_value": round_smart(per_serving_value, 4),
        "amount_per_serving_unit": amount_unit,
        "amount_per_serving_raw": (
            f"{round_smart(per_serving_value, 4)}{amount_unit or ''}"
            if per_serving_value is not None else amount_note
        ),

        "gram_per_serving": round_smart(gram_per_serving, 2),
        "gram_source": gram_source,
        "needs_llm": llm_needed,
        "llm_prompt": None,
        "llm_confidence": None,
        "llm_reason": None,
        "llm_model": None,
    }

    if llm_needed:
        llm_prompt = build_llm_prompt(
            recipe_name=recipe_name,
            servings=servings,
            ingredient=ingredient,
        )
        result["llm_prompt"] = llm_prompt

        if mode == "llm":
            try:
                llm_result = estimate_with_llm(llm_prompt)
                result["gram_per_serving"] = round_smart(llm_result["estimated_grams"], 2)
                result["gram_source"] = "llm_estimated"
                result["llm_confidence"] = llm_result.get("confidence")
                result["llm_reason"] = llm_result.get("reason")
                result["llm_model"] = llm_result.get("model")
            except Exception as e:
                result["gram_source"] = "llm_failed"
                result["llm_reason"] = f"LLM estimate failed: {str(e)}"

    return result


def preprocess_recipe(recipe: Dict[str, Any], mode: str) -> Dict[str, Any]:
    servings = get_servings(recipe)
    recipe_name = recipe.get("name", "")

    processed_ingredients = [
        preprocess_ingredient(
            ingredient=ing,
            servings=servings,
            recipe_name=recipe_name,
            mode=mode,
        )
        for ing in recipe.get("ingredients", [])
    ]

    return {
        "recipe_id": recipe.get("recipe_id"),
        "name": recipe_name,
        "original_servings": servings,
        "normalized_servings": 1,
        "ingredients": processed_ingredients,
    }


def preprocess_recipes(recipes: List[Dict[str, Any]], mode: str) -> List[Dict[str, Any]]:
    return [preprocess_recipe(recipe, mode=mode) for recipe in recipes]


# =========================================================
# 八、待 LLM 項目統計
# =========================================================

def collect_llm_candidates(processed_recipes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    candidates = []

    for recipe in processed_recipes:
        for ing in recipe.get("ingredients", []):
            if ing.get("needs_llm"):
                candidates.append({
                    "recipe_id": recipe.get("recipe_id"),
                    "recipe_name": recipe.get("name"),
                    "ingredient_name": ing.get("name"),
                    "amount_raw": ing.get("amount_raw"),
                    "amount_per_serving_raw": ing.get("amount_per_serving_raw"),
                    "gram_per_serving": ing.get("gram_per_serving"),
                    "gram_source": ing.get("gram_source"),
                    "llm_confidence": ing.get("llm_confidence"),
                    "llm_reason": ing.get("llm_reason"),
                })

    return candidates


# =========================================================
# 九、主程式
# =========================================================

def main():
    with open(INPUT_PATH, "r", encoding="utf-8") as f:
        recipes = json.load(f)

    if TEST_LIMIT is not None:
        recipes = recipes[:TEST_LIMIT]

    processed = preprocess_recipes(recipes, mode=MODE)
    llm_candidates = collect_llm_candidates(processed)

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(processed, f, ensure_ascii=False, indent=2)

    with open(LLM_CANDIDATES_OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(llm_candidates, f, ensure_ascii=False, indent=2)

    print(f"模式：{MODE}")
    print(f"完成：已輸出 {OUTPUT_PATH}")
    print(f"完成：已輸出 {LLM_CANDIDATES_OUTPUT_PATH}")
    print(f"食譜數量：{len(processed)}")
    print(f"待 LLM 項目數量：{len(llm_candidates)}")

    if processed:
        print("\n===== 第一筆食譜示範 =====")
        print(json.dumps(processed[0], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
