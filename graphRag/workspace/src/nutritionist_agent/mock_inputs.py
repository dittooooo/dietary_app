from __future__ import annotations

from typing import List

from .models import DietRecord, HealthCondition, UserProfile


# 提供本機測試用的預設使用者身體資料。
def default_user_profile() -> UserProfile:
    return UserProfile(
        height_cm=170,
        weight_kg=70,
        gender="未提供",
        age=30,
    )


# 提供本機測試用的預設健康狀況，預設帶糖尿病脈絡。
def default_health_condition() -> HealthCondition:
    return HealthCondition(
        has_chronic_disease=True,
        chronic_diseases=["糖尿病"],
    )


# 提供本機測試用的近一周飲食紀錄樣本。
def default_weekly_diet_records() -> List[DietRecord]:
    return [
        DietRecord(date="2026-05-18", meal="lunch", dish_name="雞腿便當", note="外食"),
        DietRecord(date="2026-05-19", meal="dinner", dish_name="牛肉麵", note="湯喝一半"),
        DietRecord(date="2026-05-20", meal="lunch", dish_name="滷味", note="加醬"),
    ]

