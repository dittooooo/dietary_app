from __future__ import annotations

import os
from pathlib import Path
from typing import Dict, Optional

try:
    from dotenv import dotenv_values
except ModuleNotFoundError:

    def dotenv_values(path: Path) -> Dict[str, Optional[str]]:
        values: Dict[str, Optional[str]] = {}
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
        return values


def load_env_files() -> None:
    env_paths = [
        Path(__file__).resolve().parents[2] / ".env",
        Path(__file__).resolve().parent / ".env",
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

NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_API_BASE = os.getenv("OPENAI_API_BASE", "https://api.openai.com/v1")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")

DEFAULT_TOP_N_ROWS = int(os.getenv("NUTRITION_AGENT_TOP_N_ROWS", "80"))


GRAPH_SCHEMA = """
Neo4j graph schema:

Nodes:
- (:Dish {recipe_id, name, servings})
- (:Ingredient {name, matched_food_id, matched_food_name, mapping_method})
- (:FoodItem {food_id, name, category, aliases})
- (:Nutrition {nutrition_id, name, name_zh, unit, category, source_column})
- (:Disease {disease_id, name, name_en})

Relationships:
- (:Dish)-[:CONTAINS {amount, unit, amount_per_serving, matched_food_id, matched_food_name}]->(:Ingredient)
- (:Ingredient)-[:HAS_NUTRITION {amount_per_100g, amount_per_serving, unit, source_food_id, source_food_name}]->(:Nutrition)
- (:Disease)-[:HAS_DIET_RULE {relation, direction, note, reason, food_level_condition, sources_json}]->(:Nutrition)

Main retrieval path:
Dish -> CONTAINS -> Ingredient -> HAS_NUTRITION -> Nutrition <- HAS_DIET_RULE <- Disease
""".strip()

