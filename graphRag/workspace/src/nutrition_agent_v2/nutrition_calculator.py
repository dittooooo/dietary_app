from __future__ import annotations

from collections import defaultdict
from typing import Any, Dict, List, Tuple

from .models import DishNutrition, NutrientAmount


COMMON_NUTRIENT_ALIASES = {
    "熱量": "熱量",
    "修正熱量": "熱量",
    "calories": "熱量",
    "energy": "熱量",
    "粗蛋白": "蛋白質",
    "蛋白質": "蛋白質",
    "protein": "蛋白質",
    "粗脂肪": "脂肪",
    "脂質": "脂肪",
    "脂肪": "脂肪",
    "fat": "脂肪",
    "總碳水化合物": "碳水化合物",
    "碳水化合物": "碳水化合物",
    "carbohydrate": "碳水化合物",
    "carbs": "碳水化合物",
    "糖質總量": "糖",
    "糖": "糖",
    "sugar": "糖",
    "膳食纖維": "膳食纖維",
    "fiber": "膳食纖維",
    "鈉": "鈉",
    "sodium": "鈉",
    "飽和脂肪": "飽和脂肪",
}

COMMON_NUTRIENT_ORDER = [
    "熱量",
    "蛋白質",
    "脂肪",
    "碳水化合物",
    "糖",
    "鈉",
    "膳食纖維",
    "飽和脂肪",
]

MACRO_FORMULA = "protein_g*4 + carbohydrate_g*4 + fat_g*9"


class NutritionCalculator:
    def summarize_and_recalculate(self, rows: List[Dict[str, Any]]) -> Tuple[List[DishNutrition], List[Dict[str, Any]]]:
        totals: Dict[str, Dict[str, Dict[str, Any]]] = defaultdict(dict)
        strategy_by_dish: Dict[str, str] = {}
        match_by_dish: Dict[str, Dict[str, Any]] = {}

        for row in rows:
            dish_name = row.get("dish_name")
            raw_name = row.get("nutrition_name_zh") or row.get("nutrition_name")
            display_name = COMMON_NUTRIENT_ALIASES.get(str(raw_name), str(raw_name))
            if not dish_name or display_name not in COMMON_NUTRIENT_ORDER:
                continue

            amount = row.get("amount_per_serving")
            if not isinstance(amount, (int, float)):
                continue

            unit = row.get("nutrition_unit")
            strategy_by_dish.setdefault(str(dish_name), row.get("retrieval_strategy") or "unknown")
            match_by_dish.setdefault(
                str(dish_name),
                {
                    "matched_name": row.get("matched_name") or row.get("matched_dish_name"),
                    "matched_type": row.get("matched_type"),
                    "match_score": row.get("match_score"),
                    "match_reason": row.get("match_reason"),
                },
            )
            current = totals[str(dish_name)].setdefault(display_name, {"amount": 0.0, "unit": unit})
            current["amount"] += float(amount)
            current["unit"] = current["unit"] or unit

        summaries: List[DishNutrition] = []
        nutrition_debug: List[Dict[str, Any]] = []
        for dish_name, nutrient_map in totals.items():
            calorie_debug = self._recalculate_calories(dish_name, nutrient_map)
            nutrition_debug.append(calorie_debug)

            nutrients = []
            for name in COMMON_NUTRIENT_ORDER:
                if name not in nutrient_map:
                    continue
                item = nutrient_map[name]
                nutrient = NutrientAmount(
                    name=name,
                    amount_per_serving=round(item["amount"], 2),
                    unit=item["unit"],
                )
                if name == "熱量":
                    nutrient.calculation_method = item.get("calculation_method")
                    nutrient.formula = item.get("formula")
                    nutrient.calorie_status = item.get("calorie_status")
                nutrients.append(nutrient)

            summaries.append(
                DishNutrition(
                    dish_name=dish_name,
                    matched_name=match_by_dish.get(dish_name, {}).get("matched_name"),
                    matched_type=match_by_dish.get(dish_name, {}).get("matched_type"),
                    match_score=match_by_dish.get(dish_name, {}).get("match_score"),
                    match_reason=match_by_dish.get(dish_name, {}).get("match_reason"),
                    retrieval_strategy=strategy_by_dish.get(dish_name),
                    nutrients=nutrients,
                )
            )

        return summaries, nutrition_debug

    @staticmethod
    def _recalculate_calories(dish_name: str, nutrient_map: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
        macro_values: Dict[str, float] = {}
        invalid_units = []
        for nutrient_name, macro_key in (
            ("蛋白質", "protein_g"),
            ("碳水化合物", "carbohydrate_g"),
            ("脂肪", "fat_g"),
        ):
            item = nutrient_map.get(nutrient_name)
            if not item:
                continue
            if str(item.get("unit") or "").lower() != "g":
                invalid_units.append({"nutrient": nutrient_name, "unit": item.get("unit")})
                continue
            macro_values[macro_key] = float(item["amount"])

        graph_calorie = None
        if "熱量" in nutrient_map:
            graph_calorie = round(float(nutrient_map["熱量"]["amount"]), 2)
            nutrient_map.pop("熱量", None)

        if invalid_units:
            status = "unit_invalid"
        elif {"protein_g", "carbohydrate_g", "fat_g"}.issubset(macro_values):
            calories = calculate_calories(
                macro_values["protein_g"],
                macro_values["carbohydrate_g"],
                macro_values["fat_g"],
            )
            nutrient_map["熱量"] = {
                "amount": calories,
                "unit": "kcal",
                "calculation_method": "macro_calculation",
                "formula": MACRO_FORMULA,
                "calorie_status": "calculated",
            }
            return {
                "dish_name": dish_name,
                **macro_values,
                "calories_kcal": calories,
                "graph_calories_kcal_reference": graph_calorie,
                "calorie_status": "calculated",
                "formula": MACRO_FORMULA,
            }
        else:
            status = "insufficient_macros"

        if graph_calorie is not None:
            nutrient_map["熱量"] = {
                "amount": graph_calorie,
                "unit": "kcal",
                "calculation_method": "source_data",
                "formula": None,
                "calorie_status": status,
            }

        return {
            "dish_name": dish_name,
            **macro_values,
            "calories_kcal": None,
            "graph_calories_kcal_reference": graph_calorie,
            "calorie_status": status,
            "invalid_units": invalid_units,
            "formula": MACRO_FORMULA,
        }


def calculate_calories(protein_g: float, carb_g: float, fat_g: float) -> float:
    return round(protein_g * 4 + carb_g * 4 + fat_g * 9, 2)
