from __future__ import annotations

import os
import re
from typing import Any

_ENV_VAR_PATTERN = re.compile(r"\$\{([A-Z0-9_]+)\}")


def expand_env_vars(value: Any) -> Any:
    """
    Recursively expand ${VAR} placeholders in YAML/JSON-loaded config objects.

    - If VAR is set, replaces with its value.
    - If VAR is missing, leaves the placeholder unchanged so callers can detect it.
    """
    if isinstance(value, dict):
        return {k: expand_env_vars(v) for k, v in value.items()}
    if isinstance(value, list):
        return [expand_env_vars(v) for v in value]
    if isinstance(value, str):
        return _ENV_VAR_PATTERN.sub(lambda m: os.getenv(m.group(1), m.group(0)), value)
    return value

