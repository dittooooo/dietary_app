from __future__ import annotations

"""
restaurant_finder.py - V2

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
"""

import json
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Optional
from tqdm import tqdm

import requests

from config import AppConfig, load_config


class GooglePlacesAPIError(Exception):
    """Google Places API 相關錯誤。"""


@dataclass
class SearchCenter:
    """
    搜尋中心點。
    """
    name: str
    lat: float
    lng: float


@dataclass
class Restaurant:
    """
    餐廳資料模型。
    """
    name: str
    place_id: str
    address: Optional[str]
    lat: float
    lng: float
    business_status: Optional[str] = None
    rating: Optional[float] = None
    user_ratings_total: Optional[int] = None
    google_maps_url: Optional[str] = None

    # V2 新增：記錄是從哪個中心點、哪個搜尋策略抓到的
    matched_centers: list[str] = field(default_factory=list)
    matched_types: list[str] = field(default_factory=list)
    matched_strategies: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class RestaurantFinder:
    """
    V2 搜尋器：

    搜尋策略：
    1. Nearby Search + radius
    2. Nearby Search + rankby=distance
    3. 多中心點
    4. 多 type
    """

    NEARBY_SEARCH_URL = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"

    def __init__(self, config: AppConfig):
        self.config = config

        # 你可以依需求自行微調這些中心點
        self.search_centers: list[SearchCenter] = [
            SearchCenter("淡江大學", 25.1759, 121.4505),
            SearchCenter("水源街商圈", 25.1739, 121.4518),
            SearchCenter("英專路商圈", 25.1722, 121.4460),
            SearchCenter("大忠街商圈", 25.1768, 121.4468),
            SearchCenter("淡水捷運站", 25.1679, 121.4456),
        ]

        # V2：不只查 restaurant，補足其他常見餐飲類型
        self.search_types: list[str] = [
            "restaurant",
            "meal_takeaway",
            "cafe",
            "bakery",
        ]

    def find_all_restaurants(self) -> list[Restaurant]:
        """
        V2 主搜尋流程：
        - 多中心點
        - 多 type
        - radius + distance 兩種策略
        - place_id 去重
        """
        dedup: dict[str, Restaurant] = {}

        total_tasks = len(self.search_centers) * len(self.search_types) * 2  # radius + distance

        with tqdm(total=total_tasks, desc="搜尋餐廳進度") as pbar:

            # A: radius 搜尋
            for center in self.search_centers:
                for place_type in self.search_types:
                    results = self._nearby_search_radius(
                        center=center,
                        radius_meters=self.config.search_radius_meters,
                        place_type=place_type,
                        max_pages=3,
                    )

                    self._merge_restaurants(
                        dedup=dedup,
                        restaurants=results,
                        center_name=center.name,
                        place_type=place_type,
                        strategy="nearby_radius",
                    )

                    pbar.set_postfix({
                        "center": center.name,
                        "type": place_type,
                        "mode": "radius"
                    })
                    pbar.update(1)

            # B: distance 搜尋
            for center in self.search_centers:
                for place_type in self.search_types:
                    results = self._nearby_search_distance(
                        center=center,
                        place_type=place_type,
                        max_pages=3,
                    )

                    self._merge_restaurants(
                        dedup=dedup,
                        restaurants=results,
                        center_name=center.name,
                        place_type=place_type,
                        strategy="nearby_distance",
                    )

                    pbar.set_postfix({
                        "center": center.name,
                        "type": place_type,
                        "mode": "distance"
                    })
                    pbar.update(1)

                restaurants = list(dedup.values())

                # 可依需求調整排序方式
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
        """
        將餐廳清單輸出到 test3/output/，檔名帶 timestamp。
        """
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

    def _merge_restaurants(
        self,
        dedup: dict[str, Restaurant],
        restaurants: list[Restaurant],
        center_name: str,
        place_type: str,
        strategy: str,
    ) -> None:
        """
        用 place_id 去重，並保留匹配來源資訊。
        """
        for restaurant in restaurants:
            existing = dedup.get(restaurant.place_id)

            if existing is None:
                restaurant.matched_centers.append(center_name)
                restaurant.matched_types.append(place_type)
                restaurant.matched_strategies.append(strategy)
                dedup[restaurant.place_id] = restaurant
                continue

            if center_name not in existing.matched_centers:
                existing.matched_centers.append(center_name)
            if place_type not in existing.matched_types:
                existing.matched_types.append(place_type)
            if strategy not in existing.matched_strategies:
                existing.matched_strategies.append(strategy)

    def _nearby_search_radius(
        self,
        center: SearchCenter,
        radius_meters: int,
        place_type: str,
        max_pages: int = 3,
    ) -> list[Restaurant]:
        """
        Nearby Search + radius
        """
        restaurants: list[Restaurant] = []
        next_page_token: Optional[str] = None

        for page_index in tqdm(range(max_pages), desc=f"{center.name}-{place_type}-pages", leave=False):
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

            # Google 的 next_page_token 通常要等一下才會生效
            time.sleep(2)

        return restaurants

    def _nearby_search_distance(
        self,
        center: SearchCenter,
        place_type: str,
        max_pages: int = 3,
    ) -> list[Restaurant]:
        """
        Nearby Search + rankby=distance
        注意：
        - rankby=distance 時不能帶 radius
        - 必須帶 keyword / name / type 至少一種
        """
        restaurants: list[Restaurant] = []
        next_page_token: Optional[str] = None

        for page_index in range(max_pages):
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

    def _request_nearby_search(
        self,
        center: SearchCenter,
        radius_meters: Optional[int],
        place_type: str,
        page_token: Optional[str] = None,
        rankby_distance: bool = False,
    ) -> dict[str, Any]:
        """
        呼叫 Google Places Nearby Search API。
        """
        params: dict[str, Any] = {
            "key": self.config.google_api_key,
            "location": f"{center.lat},{center.lng}",
            "language": self.config.language,
        }

        if page_token:
            params["pagetoken"] = page_token
        else:
            params["type"] = place_type

            if rankby_distance:
                params["rankby"] = "distance"
            else:
                if radius_meters is None:
                    raise ValueError("當 rankby_distance=False 時，radius_meters 不可為 None")
                params["radius"] = radius_meters

        try:
            response = requests.get(
                self.NEARBY_SEARCH_URL,
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
        """
        將 API 回傳結果解析成 Restaurant list。
        """
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
    output_path = finder.save_restaurants_to_timestamped_json(restaurants)

    print(f"找到 {len(restaurants)} 間餐廳")
    print(f"已輸出到: {output_path}")

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