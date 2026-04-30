from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv
load_dotenv()


@dataclass(frozen=True)
class AppConfig:
    """
    全域設定。

    說明：
    - GOOGLE_API_KEY：Google Places API 金鑰
    - SEARCH_LAT / SEARCH_LNG：搜尋中心點，預設為淡江大學淡水校園附近
    - SEARCH_RADIUS_METERS：搜尋半徑（公尺）
    - SEARCH_KEYWORD：搜尋關鍵字
    - SEARCH_TYPE：Google Places 類型，通常用 restaurant
    - LANGUAGE：回傳語言
    - OUTPUT_DIR：之後可供其他模組存放輸出結果
    - HTTP_TIMEOUT：HTTP 請求 timeout 秒數
    """

    google_api_key: str
    search_lat: float = 25.1759
    search_lng: float = 121.4505
    search_radius_meters: int = 1500
    search_keyword: str = "餐廳"
    search_type: str = "restaurant"
    language: str = "zh-TW"
    output_dir: Path = Path("./output")
    http_timeout: int = 20

    @property
    def search_center(self) -> tuple[float, float]:
        return (self.search_lat, self.search_lng)


def _parse_float_env(name: str, default: float) -> float:
    value = os.getenv(name)
    if value is None or value.strip() == "":
        return default
    try:
        return float(value)
    except ValueError as exc:
        raise ValueError(f"環境變數 {name} 必須是浮點數，收到: {value}") from exc


def _parse_int_env(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or value.strip() == "":
        return default
    try:
        return int(value)
    except ValueError as exc:
        raise ValueError(f"環境變數 {name} 必須是整數，收到: {value}") from exc


def load_config() -> AppConfig:
    """
    從環境變數載入設定。

    必填：
    - GOOGLE_API_KEY

    可選：
    - SEARCH_LAT
    - SEARCH_LNG
    - SEARCH_RADIUS_METERS
    - SEARCH_KEYWORD
    - SEARCH_TYPE
    - LANGUAGE
    - OUTPUT_DIR
    - HTTP_TIMEOUT
    """
    google_api_key = os.getenv("GOOGLE_API_KEY", "").strip()
    if not google_api_key:
        raise ValueError(
            "缺少 GOOGLE_API_KEY。請先設定環境變數，例如：\n"
            "Windows PowerShell: $env:GOOGLE_API_KEY='your_key'\n"
            "Linux/macOS: export GOOGLE_API_KEY='your_key'"
        )

    output_dir = Path(os.getenv("OUTPUT_DIR", "./output")).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    return AppConfig(
        google_api_key=google_api_key,
        search_lat=_parse_float_env("SEARCH_LAT", 25.1759),
        search_lng=_parse_float_env("SEARCH_LNG", 121.4505),
        search_radius_meters=_parse_int_env("SEARCH_RADIUS_METERS", 1500),
        search_keyword=os.getenv("SEARCH_KEYWORD", "餐廳").strip() or "餐廳",
        search_type=os.getenv("SEARCH_TYPE", "restaurant").strip() or "restaurant",
        language=os.getenv("LANGUAGE", "zh-TW").strip() or "zh-TW",
        output_dir=output_dir,
        http_timeout=_parse_int_env("HTTP_TIMEOUT", 20),
    )