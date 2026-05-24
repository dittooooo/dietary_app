from __future__ import annotations

from typing import Any, Dict

from .answer_generator import AnswerGenerator
from .config import DEFAULT_TOP_N_ROWS, NEO4J_PASSWORD, NEO4J_URI, NEO4J_USER
from .cypher_guard import validate_read_only_cypher
from .models import HealthCondition, NutritionAgentRequest, NutritionAgentResponse, UserProfile
from .retriever import GraphRetriever
from .text_to_cypher import TextToCypherTranslator, infer_question_type


class NutritionAgent:
    def __init__(
        self,
        *,
        neo4j_uri: str = NEO4J_URI,
        neo4j_user: str = NEO4J_USER,
        neo4j_password: str = NEO4J_PASSWORD,
    ) -> None:
        self.retriever = GraphRetriever(neo4j_uri, neo4j_user, neo4j_password)
        self.translator = TextToCypherTranslator(self.retriever.driver)
        self.answer_generator = AnswerGenerator()

    def close(self) -> None:
        self.retriever.close()

    def ask(self, request: NutritionAgentRequest) -> NutritionAgentResponse:
        user_profile = request.user_profile or UserProfile()
        health_condition = request.health_condition or HealthCondition()
        weekly_records = request.weekly_diet_records or []
        inferred_type = infer_question_type(request.question)
        effective_question_type = (
            inferred_type
            if inferred_type == "dish_comparison"
            else request.question_type or inferred_type
        )

        if request.cypher:
            cypher = request.cypher
            validate_read_only_cypher(cypher)
            question_type = effective_question_type
        else:
            translated = self.translator.translate(
                request.question,
                health_condition,
                effective_question_type,
            )
            cypher = translated["cypher"]
            question_type = translated.get("question_type", effective_question_type)  # type: ignore[assignment]

        rows = self.retriever.retrieve(cypher)
        dish_nutrition = self.retriever.summarize_dish_nutrition(rows)
        answer_payload = self.answer_generator.generate(
            question=request.question,
            question_type=question_type,  # type: ignore[arg-type]
            user_profile=user_profile,
            health_condition=health_condition,
            weekly_diet_records=weekly_records,
            dish_nutrition=dish_nutrition,
            graph_rows=rows[:DEFAULT_TOP_N_ROWS],
        )

        return NutritionAgentResponse(
            question=request.question,
            question_type=question_type,  # type: ignore[arg-type]
            dish_nutrition=dish_nutrition,
            dish_advice=answer_payload.get("dish_advice", []),
            conclusion=answer_payload.get("conclusion", ""),
            cypher_used=cypher if request.debug else None,
            graph_rows=rows if request.debug else None,
        )
