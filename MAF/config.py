from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv


REPO_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(REPO_ROOT / ".env")


@dataclass(frozen=True)
class Settings:
    openai_api_key: str
    openai_model: str
    companion_api_url: str
    dietary_agent_api_url: str
    prompt_dir: Path
    request_timeout_seconds: float = 30.0

    @classmethod
    def from_env(cls) -> "Settings":
        api_key = os.getenv("OPENAI_API_KEY", "").strip()
        if not api_key:
            raise RuntimeError("Missing OPENAI_API_KEY.")

        return cls(
            openai_api_key=api_key,
            openai_model=os.getenv("OPENAI_MODEL", "gpt-4o-mini").strip() or "gpt-4o-mini",
            companion_api_url=os.getenv("COMPANION_AGENT_API_URL", "http://localhost:3000").rstrip("/"),
            dietary_agent_api_url=os.getenv("DIETARY_AGENT_API_URL", "http://localhost:8080").rstrip("/"),
            prompt_dir=Path(
                os.getenv(
                    "COMPANION_PROMPT_DIR",
                    str(REPO_ROOT / "companion" / "companion_js" / "prompts"),
                )
            ),
            request_timeout_seconds=float(os.getenv("MAF_REQUEST_TIMEOUT_SECONDS", "30")),
        )
