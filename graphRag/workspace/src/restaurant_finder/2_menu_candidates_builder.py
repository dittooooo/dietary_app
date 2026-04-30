#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
menu_candidates_builder.py

用途：
1. 讀取 nearby_restaurants JSON
2. 過濾不適合後續抓菜單的店家
3. 計算候選分數（priority_score）
4. 輸出為 ouput 資料夾的 menu_candidates.json

使用方式：
直接修改本檔最上方的設定區，然後執行：
    python menu_candidates_builder.py
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional


# =========================================================
# 直接在這裡設定路徑與參數
# =========================================================

INPUT_JSON_PATH = Path(r"C:\Users\PARALELL\Desktop\code4\workspace\src\restaurant_finder\output\1_restaurant_finder\nearby_restaurants_20260419_152619.json")
OUTPUT_JSON_PATH = Path(r"C:\Users\PARALELL\Desktop\code4\workspace\src\restaurant_finder\output\2_menu_candidates_builder\menu_candidates.json")

# 淡江大學附近中心點，可自行微調
CENTER_LAT = 25.1759
CENTER_LNG = 121.4505

# 過濾條件
MAX_DISTANCE_KM = 2.5
MIN_RATING_COUNT = 5
TOP_K = 200


# =========================================================
# 規則設定
# =========================================================

PREFERRED_TYPES = {
    "restaurant",
    "meal_takeaway",
    "meal_delivery",
}

SECONDARY_TYPES = {
    "cafe",
    "food_court",
}

EXCLUDED_TYPES = {
    "bakery",
}

PREFERRED_CENTERS = {
    "淡江大學",
    "水源街商圈",
    "英專路商圈",
    "大忠街商圈",
    "淡水捷運站",
}

PREFERRED_STRATEGIES = {
    "nearby_radius",
    "nearby_distance",
}

EXCLUDE_NAME_KEYWORDS = {
    "星巴克",
    "麥當勞",
    "肯德基",
    "藏壽司",
    "Tasty",
    "王品",
}

LIKELY_MENU_FRIENDLY_KEYWORDS = {
    "牛肉麵",
    "麵",
    "飯",
    "便當",
    "火鍋",
    "燒肉",
    "韓國料理",
    "小吃",
    "鍋貼",
    "水餃",
    "排骨",
    "丼飯",
    "咖哩",
    "鐵板燒",
    "早午餐",
    "早餐",
}


# =========================================================
# Data model
# =========================================================

@dataclass
class MenuCandidate:
    restaurant_name: str
    place_id: str
    address: str
    lat: float
    lng: float
    google_maps_url: str
    business_status: str
    rating: Optional[float]
    user_ratings_total: int

    matched_centers: List[str]
    matched_types: List[str]
    matched_strategies: List[str]
    matched_queries: List[str]

    distance_km: Optional[float]
    priority_score: float
    candidate_level: str
    exclude_reasons: List[str]
    notes: List[str]

    # 後續抓菜單模組可直接使用
    search_queries: List[str]


# =========================================================
# Utility
# =========================================================

def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """計算兩點球面距離（公里）"""
    r = 6371.0

    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)

    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return r * c


def safe_str_list(value: Any) -> List[str]:
    if isinstance(value, list):
        return [str(x) for x in value if x is not None]
    return []


def normalize_text(text: str) -> str:
    return (text or "").strip()


def contains_any_keyword(text: str, keywords: set[str]) -> bool:
    return any(k in text for k in keywords)


# =========================================================
# Scoring
# =========================================================

def compute_priority_score(
    item: Dict[str, Any],
    distance_km: Optional[float],
) -> tuple[float, str, List[str], List[str]]:
    exclude_reasons: List[str] = []
    notes: List[str] = []
    score = 0.0

    name = normalize_text(str(item.get("name", "")))
    business_status = normalize_text(str(item.get("business_status", "")))
    matched_types = set(safe_str_list(item.get("matched_types")))
    matched_centers = set(safe_str_list(item.get("matched_centers")))
    matched_strategies = set(safe_str_list(item.get("matched_strategies")))
    matched_queries = safe_str_list(item.get("matched_queries"))
    rating = item.get("rating")
    user_ratings_total = int(item.get("user_ratings_total") or 0)

    if not name:
        exclude_reasons.append("missing_name")
    if not item.get("place_id"):
        exclude_reasons.append("missing_place_id")
    if not item.get("google_maps_url"):
        exclude_reasons.append("missing_google_maps_url")

    # 營業狀態
    if business_status != "OPERATIONAL":
        exclude_reasons.append(f"business_status_{business_status or 'unknown'}")
    else:
        score += 2.0

    # 類型
    if matched_types:
        if matched_types & PREFERRED_TYPES:
            score += 3.0
            notes.append("preferred_type")
        elif matched_types & SECONDARY_TYPES:
            score += 0.5
            notes.append("secondary_type")
        elif matched_types & EXCLUDED_TYPES:
            exclude_reasons.append("excluded_type")
        else:
            notes.append("unknown_type")
    else:
        score -= 0.5
        notes.append("missing_types")

    # 中心區域
    if matched_centers & PREFERRED_CENTERS:
        score += 2.0
        notes.append("preferred_center")

    # 搜尋策略
    if matched_strategies & PREFERRED_STRATEGIES:
        score += 1.5
        notes.append("nearby_strategy")
    if "text_search" in matched_strategies and not (matched_strategies & PREFERRED_STRATEGIES):
        score -= 0.5
        notes.append("text_search_only")

    # 距離
    if distance_km is not None:
        if distance_km <= 0.8:
            score += 3.0
            notes.append("very_close")
        elif distance_km <= 1.5:
            score += 2.0
            notes.append("close")
        elif distance_km <= 2.5:
            score += 1.0
            notes.append("acceptable_distance")
        elif distance_km <= 4.0:
            score -= 1.0
            notes.append("a_bit_far")
        else:
            exclude_reasons.append("too_far_from_tamkang")
    else:
        notes.append("missing_distance")

    # 評價
    if isinstance(rating, (int, float)):
        score += max(0.0, min(float(rating) - 3.5, 1.5))
    else:
        notes.append("missing_rating")

    # 評論數
    if user_ratings_total >= 3000:
        score += 1.5
    elif user_ratings_total >= 1000:
        score += 1.0
    elif user_ratings_total >= 100:
        score += 0.4
    elif user_ratings_total <= 0:
        score -= 0.5

    # 連鎖店降低優先度
    if contains_any_keyword(name, EXCLUDE_NAME_KEYWORDS):
        score -= 1.2
        notes.append("chain_or_less_targeted")

    # 名稱是否像一般餐館
    if contains_any_keyword(name, LIKELY_MENU_FRIENDLY_KEYWORDS):
        score += 1.2
        notes.append("menu_friendly_name")

    # matched_queries 補強
    query_blob = " | ".join(matched_queries)
    if contains_any_keyword(query_blob, LIKELY_MENU_FRIENDLY_KEYWORDS):
        score += 0.6
        notes.append("query_matches_food_keyword")

    if exclude_reasons:
        candidate_level = "excluded"
    elif score >= 8.0:
        candidate_level = "high"
    elif score >= 5.0:
        candidate_level = "medium"
    else:
        candidate_level = "low"

    return round(score, 3), candidate_level, exclude_reasons, notes


def build_search_queries(name: str, address: str) -> List[str]:
    queries = [
        f"{name} 菜單",
        f"{name} menu",
        f"{name} 價目表",
        f"{name} 淡水 菜單",
        f"{name} foodpanda",
        f"{name} ubereats",
        f"{name} google maps",
    ]

    if "淡水" in address:
        queries.append(f"{name} 淡水")
        queries.append(f"{name} 淡江大學 菜單")

    seen = set()
    result = []
    for q in queries:
        if q not in seen:
            seen.add(q)
            result.append(q)
    return result


# =========================================================
# Transform
# =========================================================

def transform_restaurant_item(
    item: Dict[str, Any],
    center_lat: float,
    center_lng: float,
    max_distance_km: float,
    min_rating_count: int,
) -> MenuCandidate:
    lat = float(item.get("lat") or 0.0)
    lng = float(item.get("lng") or 0.0)

    if lat and lng:
        distance_km = haversine_km(center_lat, center_lng, lat, lng)
    else:
        distance_km = None

    score, level, exclude_reasons, notes = compute_priority_score(item, distance_km)
    user_ratings_total = int(item.get("user_ratings_total") or 0)

    if distance_km is not None and distance_km > max_distance_km:
        if "too_far_from_tamkang" not in exclude_reasons:
            exclude_reasons.append("too_far_from_tamkang")
        level = "excluded"

    if user_ratings_total < min_rating_count:
        exclude_reasons.append("too_few_ratings")
        level = "excluded"

    name = normalize_text(str(item.get("name", "")))
    address = normalize_text(str(item.get("address", "")))

    return MenuCandidate(
        restaurant_name=name,
        place_id=normalize_text(str(item.get("place_id", ""))),
        address=address,
        lat=lat,
        lng=lng,
        google_maps_url=normalize_text(str(item.get("google_maps_url", ""))),
        business_status=normalize_text(str(item.get("business_status", ""))),
        rating=float(item["rating"]) if isinstance(item.get("rating"), (int, float)) else None,
        user_ratings_total=user_ratings_total,
        matched_centers=safe_str_list(item.get("matched_centers")),
        matched_types=safe_str_list(item.get("matched_types")),
        matched_strategies=safe_str_list(item.get("matched_strategies")),
        matched_queries=safe_str_list(item.get("matched_queries")),
        distance_km=round(distance_km, 3) if distance_km is not None else None,
        priority_score=score,
        candidate_level=level,
        exclude_reasons=exclude_reasons,
        notes=notes,
        search_queries=build_search_queries(name, address),
    )


def deduplicate_candidates(candidates: List[MenuCandidate]) -> List[MenuCandidate]:
    """
    以 place_id 為主去重；若無 place_id，再用 name + address
    保留 priority_score 較高者
    """
    best_map: Dict[str, MenuCandidate] = {}

    for candidate in candidates:
        key = candidate.place_id.strip() if candidate.place_id else f"{candidate.restaurant_name}||{candidate.address}"
        prev = best_map.get(key)
        if prev is None or candidate.priority_score > prev.priority_score:
            best_map[key] = candidate

    result = list(best_map.values())
    result.sort(key=lambda x: (x.candidate_level != "excluded", x.priority_score), reverse=True)
    return result


def build_output_summary(candidates: List[MenuCandidate]) -> Dict[str, Any]:
    high = sum(1 for c in candidates if c.candidate_level == "high")
    medium = sum(1 for c in candidates if c.candidate_level == "medium")
    low = sum(1 for c in candidates if c.candidate_level == "low")
    excluded = sum(1 for c in candidates if c.candidate_level == "excluded")

    return {
        "total_candidates": len(candidates),
        "high": high,
        "medium": medium,
        "low": low,
        "excluded": excluded,
    }


# =========================================================
# Main
# =========================================================

def main() -> None:
    raw = load_json(INPUT_JSON_PATH)
    if not isinstance(raw, list):
        raise ValueError("Input JSON must be a list of restaurant objects.")

    transformed: List[MenuCandidate] = []
    for item in raw:
        if not isinstance(item, dict):
            continue

        transformed.append(
            transform_restaurant_item(
                item=item,
                center_lat=CENTER_LAT,
                center_lng=CENTER_LNG,
                max_distance_km=MAX_DISTANCE_KM,
                min_rating_count=MIN_RATING_COUNT,
            )
        )

    deduped = deduplicate_candidates(transformed)

    non_excluded = [c for c in deduped if c.candidate_level != "excluded"]
    excluded = [c for c in deduped if c.candidate_level == "excluded"]

    non_excluded = sorted(non_excluded, key=lambda x: x.priority_score, reverse=True)[:TOP_K]
    excluded = sorted(excluded, key=lambda x: x.priority_score, reverse=True)

    output = {
        "meta": {
            "source_file": str(INPUT_JSON_PATH),
            "output_file": str(OUTPUT_JSON_PATH),
            "center_lat": CENTER_LAT,
            "center_lng": CENTER_LNG,
            "max_distance_km": MAX_DISTANCE_KM,
            "min_rating_count": MIN_RATING_COUNT,
            "top_k": TOP_K,
        },
        "summary": build_output_summary(non_excluded + excluded),
        "candidates": [asdict(c) for c in non_excluded],
        "excluded_candidates": [asdict(c) for c in excluded],
    }

    save_json(OUTPUT_JSON_PATH, output)

    print(f"Input restaurants : {len(raw)}")
    print(f"Deduped total     : {len(deduped)}")
    print(f"Kept candidates   : {len(non_excluded)}")
    print(f"Excluded          : {len(excluded)}")
    print(f"Saved to          : {OUTPUT_JSON_PATH}")


if __name__ == "__main__":
    main()