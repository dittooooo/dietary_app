from __future__ import annotations

from typing import List, Literal, Optional

from pydantic import BaseModel, Field


QuestionType = Literal["single_dish", "dish_comparison", "unknown"]


# 使用者基本身體資料，主要供 LLM 判斷 BMI 與飲食建議語氣。
class UserProfile(BaseModel):
    height_cm: Optional[float] = Field(default=None, description="身高，公分")
    weight_kg: Optional[float] = Field(default=None, description="體重，公斤")
    gender: Optional[str] = Field(default=None, description="性別")
    age: Optional[int] = Field(default=None, description="年齡")


# 使用者健康狀況，慢性病清單會用來查 Neo4j 的疾病飲食規則。
class HealthCondition(BaseModel):
    has_chronic_disease: bool = False
    chronic_diseases: List[str] = Field(default_factory=list)


# 近一周飲食紀錄中的單筆資料，作為回答時的個人化背景。
class DietRecord(BaseModel):
    date: Optional[str] = None
    meal: Optional[str] = None
    dish_name: Optional[str] = None
    note: Optional[str] = None


# POST /ask 的請求格式，包含問題、候選料理、個人資訊與近期飲食。
class NutritionAgentRequest(BaseModel):
    question: str = Field(..., description="使用者原始問題")
    dish_names: List[str] = Field(
        default_factory=list,
        description="呼叫端明確提供的料理名稱；若有值，會優先用於圖譜檢索。",
    )
    question_type: Optional[QuestionType] = None
    user_profile: Optional[UserProfile] = None
    health_condition: Optional[HealthCondition] = None
    weekly_diet_records: Optional[List[DietRecord]] = None


# POST /dish-nutrition 的請求格式，只查單一道料理的營養成分。
class DishNutritionRequest(BaseModel):
    # 飲食紀錄端傳入的原始料理名稱，後續會拿去做 Dish/FoodItem/Ingredient 配對。
    dish_name: str = Field(..., description="要查詢營養成分的單一料理名稱")


# 單一營養素的摘要值，通常代表每份料理估計含量。
class NutrientAmount(BaseModel):
    name: str
    amount_per_serving: Optional[float] = None
    unit: Optional[str] = None
    calculation_method: Optional[str] = None
    formula: Optional[str] = None
    calorie_status: Optional[str] = None


# 單一道料理的營養摘要與圖譜配對資訊。
class DishNutrition(BaseModel):
    dish_name: str
    matched_name: Optional[str] = None
    matched_type: Optional[str] = None
    match_score: Optional[int] = None
    match_reason: Optional[str] = None
    retrieval_strategy: Optional[str] = None
    nutrients: List[NutrientAmount]


# LLM 回傳的單道料理建議，並附上配對來源方便前端或除錯顯示。
class DishAdvice(BaseModel):
    dish_name: str
    matched_name: Optional[str] = None
    matched_type: Optional[str] = None
    match_score: Optional[int] = None
    match_reason: Optional[str] = None
    suitability: str
    key_reasons: List[str]
    suggestions: List[str]


# POST /ask 的回應格式，包含營養摘要、每道料理建議與總結論。
class NutritionAgentResponse(BaseModel):
    question: str
    question_type: QuestionType
    dish_nutrition: List[DishNutrition]
    dish_advice: List[DishAdvice]
    conclusion: str


# POST /dish-nutrition 的回應格式，回傳單一道料理的營養摘要。
class DishNutritionResponse(BaseModel):
    # 單一道料理的營養摘要；格式刻意沿用 /ask 裡的 dish_nutrition item，方便前端共用資料結構。
    dish_nutrition: DishNutrition
