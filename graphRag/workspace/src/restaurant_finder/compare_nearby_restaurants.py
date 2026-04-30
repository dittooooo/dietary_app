from __future__ import annotations

import json
import argparse
from pathlib import Path
from typing import Any


def load_json(path: str) -> list[dict[str, Any]]:
    file_path = Path(path)
    if not file_path.exists():
        raise FileNotFoundError(f"找不到檔案: {path}")

    with file_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, list):
        raise ValueError(f"{path} 不是 list JSON 格式")

    return data


def build_index(records: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """
    以 place_id 當唯一鍵建立索引。
    若某筆沒有 place_id，則略過。
    """
    index: dict[str, dict[str, Any]] = {}

    for item in records:
        place_id = item.get("place_id")
        if not place_id:
            continue
        index[place_id] = item

    return index


def safe_str(value: Any) -> str:
    return "" if value is None else str(value).strip()


def compare_records(
    old_index: dict[str, dict[str, Any]],
    new_index: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    old_ids = set(old_index.keys())
    new_ids = set(new_index.keys())

    only_in_old = sorted(old_ids - new_ids)
    only_in_new = sorted(new_ids - old_ids)
    in_both = sorted(old_ids & new_ids)

    changed_fields: list[dict[str, Any]] = []

    fields_to_check = [
        "name",
        "address",
        "lat",
        "lng",
        "rating",
        "user_ratings_total",
        "business_status",
    ]

    for place_id in in_both:
        old_item = old_index[place_id]
        new_item = new_index[place_id]

        diffs = {}
        for field in fields_to_check:
            old_val = old_item.get(field)
            new_val = new_item.get(field)
            if old_val != new_val:
                diffs[field] = {
                    "old": old_val,
                    "new": new_val,
                }

        if diffs:
            changed_fields.append(
                {
                    "place_id": place_id,
                    "old_name": old_item.get("name"),
                    "new_name": new_item.get("name"),
                    "diffs": diffs,
                }
            )

    return {
        "old_count": len(old_index),
        "new_count": len(new_index),
        "only_in_old": only_in_old,
        "only_in_new": only_in_new,
        "in_both_count": len(in_both),
        "changed_fields": changed_fields,
    }


def print_summary(
    result: dict[str, Any],
    old_index: dict[str, dict[str, Any]],
    new_index: dict[str, dict[str, Any]],
    show_limit: int = 20,
) -> None:
    print("=" * 60)
    print("比較結果摘要")
    print("=" * 60)
    print(f"舊檔筆數: {result['old_count']}")
    print(f"新檔筆數: {result['new_count']}")
    print(f"共同筆數: {result['in_both_count']}")
    print(f"只在舊檔: {len(result['only_in_old'])}")
    print(f"只在新檔: {len(result['only_in_new'])}")
    print(f"欄位有變化的共同店家: {len(result['changed_fields'])}")
    print()

    print("-" * 60)
    print("只在舊檔的店家")
    print("-" * 60)
    if not result["only_in_old"]:
        print("無")
    else:
        for place_id in result["only_in_old"][:show_limit]:
            item = old_index[place_id]
            print(f"{item.get('name')} | {item.get('address')} | {place_id}")
        if len(result["only_in_old"]) > show_limit:
            print(f"... 其餘 {len(result['only_in_old']) - show_limit} 筆未顯示")
    print()

    print("-" * 60)
    print("只在新檔的店家")
    print("-" * 60)
    if not result["only_in_new"]:
        print("無")
    else:
        for place_id in result["only_in_new"][:show_limit]:
            item = new_index[place_id]
            print(f"{item.get('name')} | {item.get('address')} | {place_id}")
        if len(result["only_in_new"]) > show_limit:
            print(f"... 其餘 {len(result['only_in_new']) - show_limit} 筆未顯示")
    print()

    print("-" * 60)
    print("共同店家中欄位有變化者")
    print("-" * 60)
    if not result["changed_fields"]:
        print("無")
    else:
        for item in result["changed_fields"][:show_limit]:
            print(f"{item['old_name']} | place_id={item['place_id']}")
            for field, diff in item["diffs"].items():
                print(f"  - {field}: {diff['old']} -> {diff['new']}")
        if len(result["changed_fields"]) > show_limit:
            print(f"... 其餘 {len(result['changed_fields']) - show_limit} 筆未顯示")


def save_diff_json(
    output_path: str,
    result: dict[str, Any],
    old_index: dict[str, dict[str, Any]],
    new_index: dict[str, dict[str, Any]],
) -> None:
    payload = {
        "summary": {
            "old_count": result["old_count"],
            "new_count": result["new_count"],
            "in_both_count": result["in_both_count"],
            "only_in_old_count": len(result["only_in_old"]),
            "only_in_new_count": len(result["only_in_new"]),
            "changed_fields_count": len(result["changed_fields"]),
        },
        "only_in_old": [old_index[pid] for pid in result["only_in_old"]],
        "only_in_new": [new_index[pid] for pid in result["only_in_new"]],
        "changed_fields": result["changed_fields"],
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="比較兩份 nearby_restaurants.json"
    )
    parser.add_argument("old_file", help="舊版 JSON 檔案路徑")
    parser.add_argument("new_file", help="新版 JSON 檔案路徑")
    parser.add_argument(
        "--output",
        default="compare_result.json",
        help="輸出差異 JSON 檔案路徑，預設為 compare_result.json",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="終端最多顯示幾筆差異，預設 20",
    )
    args = parser.parse_args()

    old_records = load_json(args.old_file)
    new_records = load_json(args.new_file)

    old_index = build_index(old_records)
    new_index = build_index(new_records)

    result = compare_records(old_index, new_index)

    print_summary(result, old_index, new_index, show_limit=args.limit)
    save_diff_json(args.output, result, old_index, new_index)

    print()
    print(f"差異 JSON 已輸出到: {args.output}")


if __name__ == "__main__":
    main()