from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from typing import Any, Optional

import requests

from config import AppConfig, load_config


class GooglePlacesAPIError(Exception):
    """Google Places API 相關錯誤。"""


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

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class RestaurantFinder:
    """
    使用 Google Places Nearby Search 尋找附近餐廳。
    """

    NEARBY_SEARCH_URL = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"

    def __init__(self, config: AppConfig):
        self.config = config

    def find_nearby_restaurants(
        self,
        keyword: Optional[str] = None,
        radius_meters: Optional[int] = None,
        place_type: Optional[str] = None,
        max_pages: int = 3,
    ) -> list[Restaurant]:
        """
        查詢附近餐廳。

        參數：
        - keyword: 搜尋關鍵字，預設使用 config.search_keyword
        - radius_meters: 搜尋半徑，預設使用 config.search_radius_meters
        - place_type: Places type，預設使用 config.search_type
        - max_pages: 最多抓幾頁，Google Nearby Search 最多通常 3 頁

        回傳：
        - Restaurant list
        """
        keyword = (keyword or self.config.search_keyword).strip()
        radius_meters = radius_meters or self.config.search_radius_meters
        place_type = (place_type or self.config.search_type).strip()

        restaurants: list[Restaurant] = []
        next_page_token: Optional[str] = None
        seen_place_ids: set[str] = set()

        for page_index in range(max_pages):
            payload = self._request_nearby_search(
                keyword=keyword,
                radius_meters=radius_meters,
                place_type=place_type,
                page_token=next_page_token,
            )

            page_restaurants = self._parse_restaurants(payload)

            for restaurant in page_restaurants:
                if restaurant.place_id not in seen_place_ids:
                    seen_place_ids.add(restaurant.place_id)
                    restaurants.append(restaurant)

            next_page_token = payload.get("next_page_token")
            if not next_page_token:
                break

            # Google next_page_token 可能需要短暫等待才能生效
            # 不用 sleep 的話，下一頁有時會回 INVALID_REQUEST
            import time
            time.sleep(2)

        return restaurants

    def save_restaurants_to_json(
        self,
        restaurants: list[Restaurant],
        output_path: str,
    ) -> None:
        """
        將餐廳清單輸出為 JSON。
        """
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(
                [restaurant.to_dict() for restaurant in restaurants],
                f,
                ensure_ascii=False,
                indent=2,
            )

    def _request_nearby_search(
        self,
        keyword: str,
        radius_meters: int,
        place_type: str,
        page_token: Optional[str] = None,
    ) -> dict[str, Any]:
        """
        呼叫 Google Places Nearby Search API。
        """
        params: dict[str, Any] = {
            "key": self.config.google_api_key,
            "location": f"{self.config.search_lat},{self.config.search_lng}",
            "radius": radius_meters,
            "language": self.config.language,
        }

        if page_token:
            params["pagetoken"] = page_token
        else:
            if keyword:
                params["keyword"] = keyword
            if place_type:
                params["type"] = place_type

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
        """
        用 place_id 組一個可開啟 Google Maps 的連結。
        """
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
    """
    單獨測試用：
    直接執行 python restaurant_finder.py
    """
    config = load_config()
    finder = RestaurantFinder(config)

    restaurants = finder.find_nearby_restaurants(
        keyword="", # config.search_keyword
        radius_meters=config.search_radius_meters,
        place_type=config.search_type,
        max_pages=3,
    )

    output_path = config.output_dir / "nearby_restaurants.json"
    finder.save_restaurants_to_json(restaurants, str(output_path))

    print(f"找到 {len(restaurants)} 間餐廳")
    print(f"已輸出到: {output_path}")

    # 額外印前幾筆方便檢查
    for idx, restaurant in enumerate(restaurants[:10], start=1):
        print(
            f"{idx}. {restaurant.name} | "
            f"{restaurant.address or 'N/A'} | "
            f"rating={restaurant.rating} | "
            f"{restaurant.google_maps_url}"
        )


if __name__ == "__main__":
    main()