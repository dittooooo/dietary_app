from __future__ import annotations

from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, Field


QuestionType = Literal["single_dish", "dish_comparison", "unknown"]


class UserProfile(BaseModel):
    height_cm: Optional[float] = Field(default=None, description="身高，公分")
    weight_kg: Optional[float] = Field(default=None, description="體重，公斤")
    gender: Optional[str] = Field(default=None, description="性別")
    age: Optional[int] = Field(default=None, description="年齡")


class HealthCondition(BaseModel):
    has_chronic_disease: bool = False
    chronic_diseases: List[str] = Field(default_factory=list)


class DietRecord(BaseModel):
    date: Optional[str] = None
    meal: Optional[str] = None
    dish_name: Optional[str] = None
    note: Optional[str] = None


class NutritionAgentRequest(BaseModel):
    question: str = Field(..., description="使用者原始問題")
    cypher: Optional[str] = Field(
        default=None,
        description="前置 Text-to-Cypher 模組產生的唯讀 Cypher；若未提供，暫由本模組的 text_to_cypher.py 產生。",
    )
    question_type: Optional[QuestionType] = None
    user_profile: Optional[UserProfile] = None
    health_condition: Optional[HealthCondition] = None
    weekly_diet_records: Optional[List[DietRecord]] = None
    debug: bool = False


class NutrientAmount(BaseModel):
    name: str
    amount_per_serving: Optional[float] = None
    unit: Optional[str] = None
    calculation_method: Optional[str] = None
    formula: Optional[str] = None
    calorie_status: Optional[str] = None


class DishNutrition(BaseModel):
    dish_name: str
    matched_name: Optional[str] = None
    matched_type: Optional[str] = None
    match_score: Optional[int] = None
    match_reason: Optional[str] = None
    retrieval_strategy: Optional[str] = None
    nutrients: List[NutrientAmount]


class DishAdvice(BaseModel):
    dish_name: str
    matched_name: Optional[str] = None
    matched_type: Optional[str] = None
    match_score: Optional[int] = None
    match_reason: Optional[str] = None
    suitability: str
    key_reasons: List[str]
    suggestions: List[str]


class NutritionAgentResponse(BaseModel):
    question: str
    question_type: QuestionType
    dish_nutrition: List[DishNutrition]
    dish_advice: List[DishAdvice]
    conclusion: str
    cypher_used: Optional[str] = None
    graph_rows: Optional[List[Dict[str, Any]]] = None
    debug_trace: Optional[List[Dict[str, Any]]] = None
