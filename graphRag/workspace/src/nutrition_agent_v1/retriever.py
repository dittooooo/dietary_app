from __future__ import annotations

from collections import defaultdict
from typing import Any, Dict, List, Optional

from neo4j import GraphDatabase
from neo4j.graph import Node, Path as Neo4jPath, Relationship

from .cypher_guard import validate_read_only_cypher
from .models import DishNutrition, NutrientAmount


COMMON_NUTRIENT_ALIASES = {
    "熱量": "熱量",
    "修正熱量": "熱量",
    "粗蛋白": "蛋白質",
    "粗脂肪": "脂質",
    "總碳水化合物": "碳水化合物",
    "糖質總量": "糖質總量",
    "膳食纖維": "膳食纖維",
    "鈉": "鈉",
    "飽和脂肪": "飽和脂肪",
}

COMMON_NUTRIENT_ORDER = [
    "熱量",
    "蛋白質",
    "脂質",
    "碳水化合物",
    "糖質總量",
    "膳食纖維",
    "鈉",
    "飽和脂肪",
]


class GraphRetriever:
    def __init__(self, uri: str, user: str, password: str) -> None:
        self.driver = GraphDatabase.driver(uri, auth=(user, password))

    def close(self) -> None:
        self.driver.close()

    def retrieve(self, cypher: str) -> List[Dict[str, Any]]:
        validate_read_only_cypher(cypher)
        with self.driver.session() as session:
            result = session.run(cypher)
            return [{key: self.to_plain_value(value) for key, value in record.data().items()} for record in result]

    def summarize_dish_nutrition(self, rows: List[Dict[str, Any]]) -> List[DishNutrition]:
        totals: Dict[str, Dict[str, Dict[str, Any]]] = defaultdict(dict)

        for row in rows:
            dish_name = row.get("dish_name")
            raw_name = row.get("nutrition_name_zh") or row.get("nutrition_name")
            display_name = COMMON_NUTRIENT_ALIASES.get(str(raw_name), str(raw_name))
            if not dish_name or display_name not in COMMON_NUTRIENT_ORDER:
                continue

            amount = row.get("amount_per_serving")
            if not isinstance(amount, (int, float)):
                continue

            unit = row.get("nutrition_unit")
            current = totals[dish_name].setdefault(display_name, {"amount": 0.0, "unit": unit})
            current["amount"] += float(amount)
            current["unit"] = current["unit"] or unit

        summaries: List[DishNutrition] = []
        for dish_name, nutrient_map in totals.items():
            nutrients = []
            for name in COMMON_NUTRIENT_ORDER:
                if name not in nutrient_map:
                    continue
                item = nutrient_map[name]
                nutrients.append(
                    NutrientAmount(
                        name=name,
                        amount_per_serving=round(item["amount"], 2),
                        unit=item["unit"],
                    )
                )
            summaries.append(DishNutrition(dish_name=dish_name, nutrients=nutrients))

        return summaries

    @classmethod
    def to_plain_value(cls, value: Any) -> Any:
        if isinstance(value, Node):
            return {"labels": sorted(value.labels), "properties": dict(value.items())}
        if isinstance(value, Relationship):
            return {"type": value.type, "properties": dict(value.items())}
        if isinstance(value, Neo4jPath):
            return {
                "nodes": [cls.to_plain_value(node) for node in value.nodes],
                "relationships": [cls.to_plain_value(rel) for rel in value.relationships],
            }
        if isinstance(value, list):
            return [cls.to_plain_value(item) for item in value]
        if isinstance(value, dict):
            return {key: cls.to_plain_value(item) for key, item in value.items()}
        return value

