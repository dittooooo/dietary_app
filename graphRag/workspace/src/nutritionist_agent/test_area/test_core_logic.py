from __future__ import annotations

import json
import unittest
from pathlib import Path

from src.nutritionist_agent.models import NutritionAgentRequest
from src.nutritionist_agent.nutrition_calculator import NutritionCalculator
from src.nutritionist_agent.text_to_cypher import build_graph_retrieval_cypher


class NutritionAgentCoreTests(unittest.TestCase):
    def test_sample_requests_match_api_model(self) -> None:
        data_dir = Path(__file__).resolve().parents[1] / "test_data"
        for name in ("sample_request_single_dish.json", "sample_request_comparison.json"):
            with self.subTest(name=name):
                payload = json.loads((data_dir / name).read_text(encoding="utf-8"))
                request = NutritionAgentRequest.model_validate(payload)
                self.assertTrue(request.dish_info_list)

    def test_amount_is_applied_in_graph_query(self) -> None:
        cypher = build_graph_retrieval_cypher(
            [
                {
                    "input_name": "雞腿便當",
                    "matched_dish_name": "雞腿便當",
                    "matched_food_id": None,
                    "matched_food_name": None,
                    "retrieval_strategy": "dish_match",
                    "match_score": 100,
                    "match_reason": "exact normalized match",
                    "amount": 2,
                }
            ],
            [],
        )
        self.assertIn("amount: 2", cypher)
        self.assertIn("c.amount_per_serving * target.amount", cypher)

    def test_calculator_recalculates_calories_from_macros(self) -> None:
        rows = [
            {
                "dish_name": "雞腿便當",
                "nutrition_name_zh": "蛋白質",
                "amount_per_serving": 20,
                "nutrition_unit": "g",
                "retrieval_strategy": "dish_match",
                "matched_name": "雞腿便當",
                "matched_type": "dish",
            },
            {
                "dish_name": "雞腿便當",
                "nutrition_name_zh": "碳水化合物",
                "amount_per_serving": 50,
                "nutrition_unit": "g",
                "retrieval_strategy": "dish_match",
                "matched_name": "雞腿便當",
                "matched_type": "dish",
            },
            {
                "dish_name": "雞腿便當",
                "nutrition_name_zh": "脂肪",
                "amount_per_serving": 10,
                "nutrition_unit": "g",
                "retrieval_strategy": "dish_match",
                "matched_name": "雞腿便當",
                "matched_type": "dish",
            },
        ]
        summaries, _ = NutritionCalculator().summarize_and_recalculate(rows)
        calories = next(item for item in summaries[0].nutrients if item.name == "熱量")
        self.assertEqual(calories.amount_per_serving, 370)
        self.assertEqual(calories.calorie_status, "calculated")


if __name__ == "__main__":
    unittest.main()
