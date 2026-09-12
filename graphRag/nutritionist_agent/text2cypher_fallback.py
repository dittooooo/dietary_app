from __future__ import annotations

import re
from typing import Any

from .config import OPENAI_API_BASE, OPENAI_API_KEY, OPENAI_MODEL
from .cypher_guard import validate_read_only_cypher
from .dish_matcher import lexical_match_score, normalize_name, tokenize_name


PROMPT = """
You generate one read-only Neo4j Cypher query that finds Dish or FoodItem
candidates for a food or dish phrase.

Schema:
(:Dish {recipe_id, name})-[:CONTAINS]->(:Ingredient {name})
(:Ingredient)-[:MAPS_TO]->(:FoodItem {food_id, name})

Rules:
- Use only the schema above.
- Use the parameter $query for the user's phrase; never copy it into Cypher.
- Return exactly these aliases: match_type, name, recipe_id, food_id, evidence.
- evidence must be the matched Dish, FoodItem, or Ingredient name.
- Return at most 5 rows with a numeric LIMIT.
- Never write data or use CALL, APOC, UNION, subqueries, or comments.
- Return Cypher only, without Markdown fences.

Food or dish phrase: {query}
""".strip()

REQUIRED_ALIASES = {"match_type", "name", "recipe_id", "food_id", "evidence"}
ALLOWED_GRAPH_TYPES = {"Dish", "FoodItem", "Ingredient", "CONTAINS", "MAPS_TO"}


class Text2CypherFallback:
    """Generate a bounded candidate lookup; nutrition stays on the fixed query path."""

    def __init__(self, retriever: Any) -> None:
        # Keep LangChain optional while the feature flag is off.
        from langchain_core.output_parsers import StrOutputParser
        from langchain_core.prompts import PromptTemplate
        from langchain_openai import ChatOpenAI

        self.retriever = retriever
        llm = ChatOpenAI(
            model=OPENAI_MODEL,
            temperature=0,
            api_key=OPENAI_API_KEY,
            base_url=OPENAI_API_BASE,
            timeout=8.0,
            max_retries=0,
            max_tokens=400,
        )
        self.chain = PromptTemplate.from_template(PROMPT) | llm | StrOutputParser()

    def resolve(self, query: str) -> dict[str, Any] | None:
        cypher = self._strip_fence(self.chain.invoke({"query": query}))
        self.validate(cypher)
        rows = self.retriever.retrieve(cypher, {"query": query})

        for row in rows:
            if self._is_acceptable_candidate(query, row):
                return row
        return None

    @staticmethod
    def _strip_fence(value: str) -> str:
        value = value.strip()
        value = re.sub(r"^```(?:cypher)?\s*", "", value, flags=re.IGNORECASE)
        return re.sub(r"\s*```$", "", value).strip()

    @staticmethod
    def validate(cypher: str) -> None:
        validate_read_only_cypher(cypher)
        if "//" in cypher or "/*" in cypher or "*/" in cypher:
            raise ValueError("Text2Cypher comments are not allowed.")
        if not re.search(r"\$query\b", cypher, re.IGNORECASE):
            raise ValueError("Text2Cypher must use the $query parameter.")
        if re.search(r"\b(UNION|FOREACH|EXISTS\s*\{|COUNT\s*\{)\b", cypher, re.IGNORECASE):
            raise ValueError("Text2Cypher contains an unsupported clause.")

        graph_types = set(re.findall(r":\s*`?([A-Za-z_][A-Za-z0-9_]*)`?", cypher))
        if not graph_types.issubset(ALLOWED_GRAPH_TYPES):
            raise ValueError("Text2Cypher used an unsupported graph type.")

        aliases = set(re.findall(
            r"\bAS\s+`?([A-Za-z_][A-Za-z0-9_]*)`?", cypher, re.IGNORECASE
        ))
        if aliases != REQUIRED_ALIASES:
            raise ValueError("Text2Cypher return schema is invalid.")

        limits = re.findall(r"\bLIMIT\s+(\d+)\b", cypher, re.IGNORECASE)
        if len(limits) != 1 or int(limits[0]) > 5:
            raise ValueError("Text2Cypher LIMIT must be a single value from 1 to 5.")
        if int(limits[0]) < 1:
            raise ValueError("Text2Cypher LIMIT must be a single value from 1 to 5.")

    @staticmethod
    def _is_acceptable_candidate(query: str, row: dict[str, Any]) -> bool:
        match_type = row.get("match_type")
        name = normalize_name(str(row.get("name") or ""))
        evidence = normalize_name(str(row.get("evidence") or ""))
        normalized_query = normalize_name(query)
        if match_type not in {"dish", "food_item"} or not name or not evidence:
            return False
        if match_type == "dish" and not row.get("recipe_id"):
            return False
        if match_type == "food_item" and not row.get("food_id"):
            return False
        if evidence in normalized_query or normalized_query in evidence:
            return True
        return lexical_match_score(
            tokenize_name(normalized_query), tokenize_name(evidence)
        ) >= 60
