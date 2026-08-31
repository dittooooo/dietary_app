from __future__ import annotations
from typing import List, Literal, Optional

from pydantic import BaseModel, Field, field_validator

QuestionType = Literal["single_dish", "dish_comparison", "unknown"]
Suitability = Literal["推薦", "較不建議", "適合", "可少量吃", "不建議", "資料不足"]
class UserProfile(BaseModel):
    height_cm: Optional[float] = None
    weight_kg: Optional[float] = None
    gender: Optional[str] = None
    age: Optional[int] = None
    diet_goal: Optional[str] = None
class HealthCondition(BaseModel):
    has_chronic_disease: bool = False
    chronic_diseases: List[str] = Field(default_factory=list)
class DietRecordNutrition(BaseModel):
    calories: Optional[float] = None
    protein: Optional[float] = None
    fat: Optional[float] = None
    carbohydrates: Optional[float] = None
class DietRecordItem(BaseModel):
    dish_name: str
    meal_type: Optional[str] = None
    nutrition: Optional[DietRecordNutrition] = None
    amount: Optional[float] = None
    note: Optional[str] = None
class DietRecord(BaseModel):
    date: Optional[str] = None
    record: List[DietRecordItem] = Field(default_factory=list)
class DishInfo(BaseModel):
    dish_name: str
    amount: float = Field(default=1, gt=0, allow_inf_nan=False, description="Number of servings for this dish")

    @field_validator("dish_name")
    @classmethod
    def nonempty_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("dish_name must not be blank")
        return value
class NutritionAgentRequest(BaseModel):
    question: str
    question_type: QuestionType
    dish_info_list: List[DishInfo] = Field(min_length=1)
    user_profile: Optional[UserProfile] = None
    health_condition: Optional[HealthCondition] = None
    weekly_diet_records: Optional[List[DietRecord]] = None
class DishNutritionRequest(BaseModel):
    dish_name: str
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
    suitability: Suitability
    key_reasons: List[str]
    suggestions: List[str]
class NutritionAgentResponse(BaseModel):
    question: str
    question_type: QuestionType
    dish_nutrition: List[DishNutrition]
    dish_advice: List[DishAdvice]
    conclusion: str
class DishNutritionResponse(BaseModel):
    dish_nutrition: DishNutrition
