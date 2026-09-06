from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


BASE_DIR = Path(__file__).resolve().parents[2]
DEFAULT_INPUT = BASE_DIR / "output" / "recipes_r_from_neo4j_deduplicated_20260827.json"

MUTABLE_AMOUNT_FIELDS = {
    "amount_value",
    "amount_per_serving",
    "amount_unit",
    "amount_raw",
    "amount_note",
}


def clean_text(value: Any) -> str:
    return str(value or "").strip()


def normalized(value: Any) -> str:
    return re.sub(r"\s+", "", clean_text(value)).casefold()


def number(value: Any) -> float | None:
    if value in (None, "") or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def format_number(value: float) -> int | float:
    rounded = round(value, 2)
    return int(rounded) if rounded.is_integer() else rounded


def density_for_ingredient(original: Any, matched: Any) -> Tuple[float, str]:
    text = normalized(f"{clean_text(original)} {clean_text(matched)}")

    density_rules = [
        (("蜂蜜", "蜂蜜"), 1.42, "honey"),
        (("糖漿", "糖蜜", "糖水"), 1.30, "syrup"),
        (("果醬", "果泥", "醬"), 1.15, "sauce_or_jam"),
        (("番茄醬", "蕃茄醬", "沙拉醬", "美乃滋", "蛋黃醬"), 1.10, "thick_sauce"),
        (("醬油膏", "蠔油", "蚵油", "魚露"), 1.20, "seasoning_sauce"),
        (("醬油", "生抽", "味醂", "米醋", "白醋", "烏醋", "醋"), 1.10, "liquid_seasoning"),
        (("鮮奶油", "奶油白醬", "奶油(液態)", "奶油液態"), 1.00, "cream_or_liquid_butter"),
        (("牛奶", "鮮奶", "乳", "奶", "豆漿", "燕麥奶", "椰奶"), 1.03, "milk_or_plant_milk"),
        (("油", "麻油", "香油", "橄欖油", "沙拉油", "植物油", "奶油"), 0.92, "oil_or_butter"),
        (("紅酒", "白酒", "白葡萄酒", "紹興酒", "米酒", "清酒", "啤酒", "威士忌", "蘭姆酒", "伏特加", "酒"), 0.95, "alcohol"),
        (("檸檬汁", "柳橙汁", "蘋果汁", "果汁", "咖啡", "茶", "氣泡水", "水", "高湯", "湯"), 1.00, "water_based_liquid"),
    ]
    for markers, density, label in density_rules:
        if any(marker in text for marker in markers):
            return density, label
    return 1.00, "default_liquid_density"


def mass_factor(unit: Any, original: Any, matched: Any) -> Tuple[float, str]:
    key = normalized(unit)
    if key in {"g", "克", "公克", "gram", "grams"}:
        return 1.0, "already_mass_g"
    if key in {"ml", "毫升", "cc", "c.c.", "c.c", "立方公分"}:
        density, label = density_for_ingredient(original, matched)
        return density, label
    if key in {"mg", "毫克"}:
        return 0.001, "milligram_to_gram"
    if key in {"kg", "公斤", "千克"}:
        return 1000.0, "kilogram_to_gram"
    if key in {"lb", "磅"}:
        return 453.59237, "pound_to_gram"
    if key in {"oz", "盎司"}:
        return 28.349523125, "ounce_to_gram"
    if key in {"斤"}:
        return 600.0, "taiwan_jin_to_gram"
    if key in {"兩", "两", "台兩", "台两"}:
        return 37.5, "taiwan_liang_to_gram"
    raise ValueError(f"Unsupported amount unit: {unit!r} for {original!r} -> {matched!r}")


RAW_UNIT_PATTERN = re.compile(
    r"(?P<first>\d+(?:\.\d+)?)\s*"
    r"(?:(?P<separator>[-~～至])\s*(?P<second>\d+(?:\.\d+)?)\s*)?"
    r"(?P<unit>毫升|ml|mL|cc|c\.c\.?|立方公分|公升|升|l|L|毫克|mg|克|公克|g|公斤|kg|斤|兩|两|台兩|台两)"
)


def raw_unit_factor(unit: str, original: Any, matched: Any) -> Tuple[float, str]:
    key = normalized(unit)
    if key in {"公升", "升", "l"}:
        density, label = density_for_ingredient(original, matched)
        return 1000.0 * density, f"liter_to_gram_{label}"
    return mass_factor(unit, original, matched)


def normalize_amount_text(value: Any, original: Any, matched: Any, additional_factor: float = 1.0) -> Any:
    if value in (None, ""):
        return value
    raw = str(value)

    def replace(match: re.Match[str]) -> str:
        factor, _ = raw_unit_factor(match.group("unit"), original, matched)
        factor *= additional_factor
        first = format_number(float(match.group("first")) * factor)
        second = match.group("second")
        if second is None:
            return f"{first}g"
        return f"{first}{match.group('separator')}{format_number(float(second) * factor)}g"

    return RAW_UNIT_PATTERN.sub(replace, raw)


def canonical_raw_amount(value: Any, converted_amount: Any, original: Any, matched: Any, additional_factor: float = 1.0) -> Any:
    normalized_raw = normalize_amount_text(value, original, matched, additional_factor)
    if normalized_raw in (None, ""):
        return normalized_raw
    if "g" in str(normalized_raw).casefold():
        return normalized_raw
    converted = number(converted_amount)
    return f"{format_number(converted)}g" if converted is not None else normalized_raw


def iter_ingredients(records: Iterable[Dict[str, Any]]) -> Iterable[Dict[str, Any]]:
    for recipe in records:
        for item in recipe.get("resolved_ingredients", []):
            yield item


def transform(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    unit_counts: Counter[str] = Counter()
    conversion_counts: Counter[str] = Counter()
    density_counts: Counter[str] = Counter()
    changed_rows = 0
    obvious_outlier_repairs = 0
    missing_numeric: List[str] = []

    for recipe in records:
        recipe_id = clean_text(recipe.get("recipe_id"))
        for item in recipe.get("resolved_ingredients", []):
            original = item.get("original")
            matched = item.get("matched")
            unit = item.get("amount_unit")
            factor, conversion_type = mass_factor(unit, original, matched)
            unit_counts[clean_text(unit) or "<empty>"] += 1
            conversion_counts[conversion_type] += 1
            if conversion_type not in {"already_mass_g"}:
                density_counts[conversion_type] += 1

            before = (
                item.get("amount_value"),
                item.get("amount_per_serving"),
                item.get("amount_unit"),
                item.get("amount_raw"),
                item.get("amount_note"),
            )
            original_value = number(item.get("amount_value"))
            original_per_serving = number(item.get("amount_per_serving"))
            additional_factor = 1.0

            # Three water rows contain an obvious 1000x data-entry error (400000g).
            # Repair only this unambiguous case; do not cap or reshape ordinary recipe quantities.
            ingredient_text = normalized(f"{clean_text(original)} {clean_text(matched)}")
            if (
                conversion_type == "already_mass_g"
                and "水" in ingredient_text
                and original_value is not None
                and original_per_serving is not None
                and original_value >= 10000
                and original_per_serving >= 10000
                and original_value % 1000 == 0
                and original_per_serving % 1000 == 0
            ):
                factor *= 0.001
                additional_factor = 0.001
                conversion_counts["obvious_1000x_outlier_repair"] += 1
                obvious_outlier_repairs += 1
            for field in ("amount_value", "amount_per_serving"):
                value = number(item.get(field))
                if value is None:
                    missing_numeric.append(f"{recipe_id}:{clean_text(original)}:{field}")
                else:
                    item[field] = format_number(value * factor)
            item["amount_unit"] = "g"
            item["amount_raw"] = canonical_raw_amount(
                item.get("amount_raw"), item.get("amount_value"), original, matched, additional_factor
            )
            item["amount_note"] = normalize_amount_text(item.get("amount_note"), original, matched, additional_factor)
            after = (
                item.get("amount_value"),
                item.get("amount_per_serving"),
                item.get("amount_unit"),
                item.get("amount_raw"),
                item.get("amount_note"),
            )
            if before != after:
                changed_rows += 1

    if missing_numeric:
        raise ValueError("Missing numeric amount fields: " + ", ".join(missing_numeric[:20]))

    return {
        "recipes": len(records),
        "ingredients": sum(1 for _ in iter_ingredients(records)),
        "changed_rows": changed_rows,
        "obvious_outlier_repairs": obvious_outlier_repairs,
        "unit_counts_before": dict(unit_counts),
        "conversion_counts": dict(conversion_counts),
        "density_conversion_counts": dict(density_counts),
    }


def non_amount_projection(value: Any) -> Any:
    if isinstance(value, list):
        return [non_amount_projection(row) for row in value]
    if isinstance(value, dict):
        return {
            key: non_amount_projection(item)
            for key, item in value.items()
            if key not in MUTABLE_AMOUNT_FIELDS
        }
    return value


def write_atomically(path: Path, records: List[Dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.stem}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        temp_path = Path(handle.name)
        json.dump(records, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.replace(temp_path, path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Normalize recipe amount fields to grams without changing other fields.")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = args.output or args.input

    original = json.loads(args.input.read_text(encoding="utf-8"))
    if not isinstance(original, list):
        raise ValueError("Recipe mapping JSON must be a list")
    records = json.loads(json.dumps(original, ensure_ascii=False))
    report = transform(records)

    if non_amount_projection(original) != non_amount_projection(records):
        raise AssertionError("Non-amount fields changed during normalization")
    write_atomically(output, records)

    remaining_units = Counter(
        clean_text(item.get("amount_unit"))
        for item in iter_ingredients(records)
    )
    report["unit_counts_after"] = dict(remaining_units)
    report["output"] = str(output)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
