from __future__ import annotations

import os
from pathlib import Path
from typing import Dict, Optional

try:
    from dotenv import dotenv_values
except ModuleNotFoundError:

    # 在未安裝 python-dotenv 時，用簡易 parser 讀取 .env key=value。
    def dotenv_values(path: Path) -> Dict[str, Optional[str]]:
        values: Dict[str, Optional[str]] = {}
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
        return values


# 僅從 dietary_app 根目錄載入 .env；部署環境已設定的變數仍優先。
def load_env_files() -> None:
    env_paths = [
        Path(__file__).resolve().parents[2] / ".env",
    ]
    placeholder_values = {"", "dummy-key"}

    for env_path in env_paths:
        if not env_path.exists():
            continue
        for key, value in dotenv_values(env_path).items():
            if value is None:
                continue
            if os.getenv(key, "") in placeholder_values:
                os.environ[key] = value


load_env_files()

# 以下設定在模組匯入時就固定，供 app、agent、retriever 與 answer_generator 使用。
APP_ENV = os.getenv("APP_ENV", "local").lower()
IS_PRODUCTION = APP_ENV in {"production", "prod"}

NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_API_BASE = os.getenv("OPENAI_API_BASE", "https://api.openai.com/v1")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.6-luna")

DEFAULT_TOP_N_ROWS = int(os.getenv("NUTRITION_AGENT_TOP_N_ROWS", "80"))
DISH_MATCH_THRESHOLD = int(os.getenv("NUTRITION_AGENT_DISH_MATCH_THRESHOLD", "60"))
DISH_BM25_TOP_K = int(os.getenv("NUTRITION_AGENT_DISH_BM25_TOP_K", "20"))
DISH_MATCH_MIN_MARGIN = int(os.getenv("NUTRITION_AGENT_DISH_MATCH_MIN_MARGIN", "5"))
GRAPH_QUERY_LIMIT = int(os.getenv("NUTRITION_AGENT_GRAPH_QUERY_LIMIT", "1000"))


# 正式環境啟動時檢查必要設定，避免用 dummy-key 或預設密碼上線。
def validate_required_config() -> None:
    if not IS_PRODUCTION:
        return

    missing = [
        key
        for key in ("OPENAI_API_KEY", "NEO4J_URI", "NEO4J_USER", "NEO4J_PASSWORD")
        if not os.getenv(key) or os.getenv(key) in {"dummy-key", "password"}
    ]
    if missing:
        joined = ", ".join(missing)
        raise RuntimeError(f"Missing required production environment variables: {joined}")
