from __future__ import annotations

"""
restaurant_finder.py - V3

版本變更紀錄（changelog）
V1:
- 使用 Google Places Nearby Search 尋找淡江大學附近餐廳
- 支援基本分頁抓取
- 支援 JSON 輸出
- 以 place_id 去重

V2:
- 新增多中心點搜尋，降低單一中心點漏店問題
- 新增多 type 搜尋，補足僅用 restaurant 類型造成的漏抓
- 新增 rankby=distance 搜尋，補足 prominence 排序偏向熱門店的問題
- 新增搜尋來源資訊欄位，方便日後除錯
- 輸出檔名改為帶 timestamp
- 輸出路徑固定為 test3/output/

V3:
- 新增 Text Search 類別模板補漏層
- 將 Nearby Search 與 Text Search 結果整合
- 新增 tqdm 進度條
- 新增搜尋統計資訊輸出
- 保留 place_id 去重，並記錄 matched_queries
"""

import json
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

import requests
from tqdm import tqdm

from config import AppConfig, load_config


class GooglePlacesAPIError(Exception):
    """Google Places API 相關錯誤。"""


@dataclass
class SearchCenter:
    name: str
    lat: float
    lng: float


@dataclass
class Restaurant:
    name: str
    place_id: str
    address: Optional[str]
    lat: float
    lng: float
    business_status: Optional[str] = None
    rating: Optional[float] = None
    user_ratings_total: Optional[int] = None
    google_maps_url: Optional[str] = None

    matched_centers: list[str] = field(default_factory=list)
    matched_types: list[str] = field(default_factory=list)
    matched_strategies: list[str] = field(default_factory=list)
    matched_queries: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class RestaurantFinder:
    NEARBY_SEARCH_URL = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
    TEXT_SEARCH_URL = "https://maps.googleapis.com/maps/api/place/textsearch/json"

    def __init__(self, config: AppConfig):
        self.config = config

        self.search_centers: list[SearchCenter] = [
            SearchCenter("淡江大學", 25.1759, 121.4505),
            SearchCenter("水源街商圈", 25.1739, 121.4518),
            SearchCenter("英專路商圈", 25.1722, 121.4460),
            SearchCenter("大忠街商圈", 25.1768, 121.4468),
            SearchCenter("淡水捷運站", 25.1679, 121.4456),
        ]

        self.search_types: list[str] = [
            "restaurant",
            "meal_takeaway",
            "cafe",
            "bakery",
        ]

        # V3: Text Search 模板清單
        self.text_search_templates: list[str] = [
            # 核心模板
            "麵店 near 淡江大學",
            "牛肉麵 near 淡江大學",
            "拉麵 near 淡江大學",
            "水餃 near 淡江大學",
            "便當 near 淡江大學",
            "小吃 near 淡江大學",
            "餐廳 near 淡江大學",
            "美食 near 淡江大學",
            "早餐店 near 淡江大學",
            "早午餐 near 淡江大學",
            "宵夜 near 淡江大學",
            "咖啡廳 near 淡江大學",

            # 擴充模板
            "丼飯 near 淡江大學",
            "炒飯 near 淡江大學",
            "義大利麵 near 淡江大學",
            "漢堡 near 淡江大學",
            "滷味 near 淡江大學",
            "鹽酥雞 near 淡江大學",
            "炸物 near 淡江大學",
            "火鍋 near 淡江大學",
            "燒烤 near 淡江大學",
            "日式料理 near 淡江大學",
            "韓式料理 near 淡江大學",
            "美式餐廳 near 淡江大學",

            # 泛化模板
            "吃的 near 淡江大學",
            "附近美食 near 淡江大學",
        ]

        self.stats: dict[str, Any] = {
            "nearby_radius_calls": 0,
            "nearby_distance_calls": 0,
            "text_search_calls": 0,
            "nearby_radius_results_raw": 0,
            "nearby_distance_results_raw": 0,
            "text_search_results_raw": 0,
            "dedup_unique_restaurants": 0,
        }

    def find_all_restaurants(self) -> list[Restaurant]:
        dedup: dict[str, Restaurant] = {}

        total_nearby_tasks = len(self.search_centers) * len(self.search_types) * 2
        total_text_tasks = len(self.text_search_templates)
        total_tasks = total_nearby_tasks + total_text_tasks

        with tqdm(total=total_tasks, desc="搜尋餐廳進度") as pbar:
            # A: Nearby radius
            for center in self.search_centers:
                for place_type in self.search_types:
                    results = self._nearby_search_radius(
                        center=center,
                        radius_meters=self.config.search_radius_meters,
                        place_type=place_type,
                        max_pages=3,
                    )
                    self.stats["nearby_radius_calls"] += 1
                    self.stats["nearby_radius_results_raw"] += len(results)

                    self._merge_restaurants(
                        dedup=dedup,
                        restaurants=results,
                        center_name=center.name,
                        place_type=place_type,
                        strategy="nearby_radius",
                        query=None,
                    )

                    pbar.set_postfix({
                        "phase": "radius",
                        "center": center.name,
                        "type": place_type,
                    })
                    pbar.update(1)

            # B: Nearby distance
            for center in self.search_centers:
                for place_type in self.search_types:
                    results = self._nearby_search_distance(
                        center=center,
                        place_type=place_type,
                        max_pages=3,
                    )
                    self.stats["nearby_distance_calls"] += 1
                    self.stats["nearby_distance_results_raw"] += len(results)

                    self._merge_restaurants(
                        dedup=dedup,
                        restaurants=results,
                        center_name=center.name,
                        place_type=place_type,
                        strategy="nearby_distance",
                        query=None,
                    )

                    pbar.set_postfix({
                        "phase": "distance",
                        "center": center.name,
                        "type": place_type,
                    })
                    pbar.update(1)

            # C: Text Search
            for query in self.text_search_templates:
                results = self._text_search(query=query, max_pages=1)
                self.stats["text_search_calls"] += 1
                self.stats["text_search_results_raw"] += len(results)

                self._merge_restaurants(
                    dedup=dedup,
                    restaurants=results,
                    center_name=None,
                    place_type=None,
                    strategy="text_search",
                    query=query,
                )

                pbar.set_postfix({
                    "phase": "text",
                    "query": query[:20],
                })
                pbar.update(1)

        restaurants = list(dedup.values())
        self.stats["dedup_unique_restaurants"] = len(restaurants)

        restaurants.sort(
            key=lambda r: (
                -(r.user_ratings_total or 0),
                -(r.rating or 0.0),
                r.name,
            )
        )

        return restaurants

    def save_restaurants_to_timestamped_json(
        self,
        restaurants: list[Restaurant],
    ) -> Path:
        script_dir = Path(__file__).resolve().parent
        output_dir = script_dir / "output"
        output_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_path = output_dir / f"nearby_restaurants_{timestamp}.json"

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(
                [restaurant.to_dict() for restaurant in restaurants],
                f,
                ensure_ascii=False,
                indent=2,
            )

        return output_path

    def save_stats_to_timestamped_json(self) -> Path:
        script_dir = Path(__file__).resolve().parent
        output_dir = script_dir / "output"
        output_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_path = output_dir / f"search_stats_{timestamp}.json"

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(self.stats, f, ensure_ascii=False, indent=2)

        return output_path

    def _merge_restaurants(
        self,
        dedup: dict[str, Restaurant],
        restaurants: list[Restaurant],
        center_name: Optional[str],
        place_type: Optional[str],
        strategy: str,
        query: Optional[str],
    ) -> None:
        for restaurant in restaurants:
            existing = dedup.get(restaurant.place_id)

            if existing is None:
                if center_name and center_name not in restaurant.matched_centers:
                    restaurant.matched_centers.append(center_name)
                if place_type and place_type not in restaurant.matched_types:
                    restaurant.matched_types.append(place_type)
                if strategy not in restaurant.matched_strategies:
                    restaurant.matched_strategies.append(strategy)
                if query and query not in restaurant.matched_queries:
                    restaurant.matched_queries.append(query)

                dedup[restaurant.place_id] = restaurant
                continue

            if center_name and center_name not in existing.matched_centers:
                existing.matched_centers.append(center_name)
            if place_type and place_type not in existing.matched_types:
                existing.matched_types.append(place_type)
            if strategy not in existing.matched_strategies:
                existing.matched_strategies.append(strategy)
            if query and query not in existing.matched_queries:
                existing.matched_queries.append(query)

    def _nearby_search_radius(
        self,
        center: SearchCenter,
        radius_meters: int,
        place_type: str,
        max_pages: int = 3,
    ) -> list[Restaurant]:
        restaurants: list[Restaurant] = []
        next_page_token: Optional[str] = None

        for _ in range(max_pages):
            payload = self._request_nearby_search(
                center=center,
                radius_meters=radius_meters,
                place_type=place_type,
                page_token=next_page_token,
                rankby_distance=False,
            )

            page_restaurants = self._parse_restaurants(payload)
            restaurants.extend(page_restaurants)

            next_page_token = payload.get("next_page_token")
            if not next_page_token:
                break

            time.sleep(2)

        return restaurants

    def _nearby_search_distance(
        self,
        center: SearchCenter,
        place_type: str,
        max_pages: int = 3,
    ) -> list[Restaurant]:
        restaurants: list[Restaurant] = []
        next_page_token: Optional[str] = None

        for _ in range(max_pages):
            payload = self._request_nearby_search(
                center=center,
                radius_meters=None,
                place_type=place_type,
                page_token=next_page_token,
                rankby_distance=True,
            )

            page_restaurants = self._parse_restaurants(payload)
            restaurants.extend(page_restaurants)

            next_page_token = payload.get("next_page_token")
            if not next_page_token:
                break

            time.sleep(2)

        return restaurants

    def _text_search(
        self,
        query: str,
        max_pages: int = 2,
    ) -> list[Restaurant]:
        restaurants: list[Restaurant] = []
        next_page_token: Optional[str] = None

        for _ in range(max_pages):
            payload = self._request_text_search(
                query=query,
                page_token=next_page_token,
            )

            page_restaurants = self._parse_restaurants(payload)
            restaurants.extend(page_restaurants)

            next_page_token = payload.get("next_page_token")
            if not next_page_token:
                break

            time.sleep(2)

        return restaurants

    def _request_nearby_search(
        self,
        center: SearchCenter,
        radius_meters: Optional[int],
        place_type: str,
        page_token: Optional[str] = None,
        rankby_distance: bool = False,
    ) -> dict[str, Any]:
        if page_token:
            params = {
                "key": self.config.google_api_key,
                "pagetoken": page_token,
            }
        else:
            params = {
                "key": self.config.google_api_key,
                "location": f"{center.lat},{center.lng}",
                "language": self.config.language,
                "type": place_type,
            }

            if rankby_distance:
                params["rankby"] = "distance"
            else:
                if radius_meters is None:
                    raise ValueError("當 rankby_distance=False 時，radius_meters 不可為 None")
                params["radius"] = radius_meters

        return self._make_request(self.NEARBY_SEARCH_URL, params)

    def _request_text_search(
        self,
        query: str,
        page_token: Optional[str] = None,
    ) -> dict[str, Any]:
        if page_token:
            params = {
                "key": self.config.google_api_key,
                "pagetoken": page_token,
            }
        else:
            params = {
                "key": self.config.google_api_key,
                "query": query,
                "language": self.config.language,
            }

        return self._make_request(self.TEXT_SEARCH_URL, params)

    def _make_request(self, url: str, params: dict[str, Any]) -> dict[str, Any]:
        try:
            response = requests.get(
                url,
                params=params,
                timeout=self.config.http_timeout,
            )
            response.raise_for_status()
        except requests.RequestException as exc:
            raise GooglePlacesAPIError(f"Google Places API 請求失敗: {exc}") from exc

        try:
            data = response.json()
        except ValueError as exc:
            raise GooglePlacesAPIError("Google Places API 回傳非 JSON 格式") from exc

        status = data.get("status")
        if status not in {"OK", "ZERO_RESULTS"}:
            error_message = data.get("error_message", "")
            raise GooglePlacesAPIError(
                f"Google Places API 錯誤，status={status}, error_message={error_message}"
            )

        return data

    def _parse_restaurants(self, payload: dict[str, Any]) -> list[Restaurant]:
        results = payload.get("results", [])
        restaurants: list[Restaurant] = []

        for item in results:
            geometry = item.get("geometry", {})
            location = geometry.get("location", {})

            place_id = item.get("place_id")
            name = item.get("name")

            if not place_id or not name:
                continue

            lat = location.get("lat")
            lng = location.get("lng")
            if lat is None or lng is None:
                continue

            restaurant = Restaurant(
                name=name,
                place_id=place_id,
                address=item.get("vicinity") or item.get("formatted_address"),
                lat=float(lat),
                lng=float(lng),
                business_status=item.get("business_status"),
                rating=self._safe_float(item.get("rating")),
                user_ratings_total=self._safe_int(item.get("user_ratings_total")),
                google_maps_url=self._build_google_maps_url(place_id),
            )
            restaurants.append(restaurant)

        return restaurants

    @staticmethod
    def _build_google_maps_url(place_id: str) -> str:
        return f"https://www.google.com/maps/place/?q=place_id:{place_id}"

    @staticmethod
    def _safe_float(value: Any) -> Optional[float]:
        if value is None:
            return None
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _safe_int(value: Any) -> Optional[int]:
        if value is None:
            return None
        try:
            return int(value)
        except (TypeError, ValueError):
            return None


def main() -> None:
    config = load_config()
    finder = RestaurantFinder(config)

    restaurants = finder.find_all_restaurants()
    restaurant_output_path = finder.save_restaurants_to_timestamped_json(restaurants)
    stats_output_path = finder.save_stats_to_timestamped_json()

    print(f"\n找到 {len(restaurants)} 間餐廳")
    print(f"餐廳結果已輸出到: {restaurant_output_path}")
    print(f"統計結果已輸出到: {stats_output_path}")

    print("\n搜尋統計：")
    for key, value in finder.stats.items():
        print(f"- {key}: {value}")

    print("\n前 10 筆結果預覽：")
    for idx, restaurant in enumerate(restaurants[:10], start=1):
        print(
            f"{idx}. {restaurant.name} | "
            f"{restaurant.address or 'N/A'} | "
            f"rating={restaurant.rating} | "
            f"types={restaurant.matched_types} | "
            f"strategies={restaurant.matched_strategies}"
        )


if __name__ == "__main__":
    main()