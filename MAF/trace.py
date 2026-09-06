from __future__ import annotations

import logging
import json
from contextvars import ContextVar, Token
from typing import Any


TRACE_HEADER = "X-Trace-Id"
_trace_id: ContextVar[str] = ContextVar("maf_trace_id", default="-")

logging.basicConfig(level=logging.INFO, format="%(message)s", force=True)
logger = logging.getLogger("maf.workflow")


def set_trace_id(value: str) -> Token[str]:
    return _trace_id.set(value)


def reset_trace_id(token: Token[str]) -> None:
    _trace_id.reset(token)


def get_trace_id() -> str:
    return _trace_id.get()


def summarize(value: Any, limit: int = 80) -> str:
    text = " ".join(str(value or "").split())
    return text if len(text) <= limit else f"{text[:limit]}…"


def trace(actor: str, state: str, message: str, *, level: int = logging.INFO) -> None:
    logger.log(level, "[%s] [%s] [%s] %s", get_trace_id(), actor, state, message)


def _redact(value: Any) -> Any:
    if isinstance(value, dict):
        hidden = {"authorization", "token", "access_token", "refresh_token", "api_key", "password"}
        private = {"user_profile", "health_condition", "weekly_diet_records"}
        return {
            str(key): "[REDACTED]" if str(key).lower() in hidden | private else _redact(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [_redact(item) for item in value]
    return value


def trace_payload(actor: str, state: str, label: str, payload: Any) -> None:
    safe = json.dumps(_redact(payload), ensure_ascii=False, default=str, separators=(",", ":"))
    logger.info("[%s] [%s] [%s] %s=%s", get_trace_id(), actor, state, label, safe)
