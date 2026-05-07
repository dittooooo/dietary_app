package com.tku.dietary_app.entity;

import java.util.Locale;

public enum MealType {
    BREAKFAST,
    LUNCH,
    DINNER;

    public static MealType from(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }

        return switch (value.trim().toUpperCase(Locale.ROOT)) {
            case "BREAKFAST", "早餐" -> BREAKFAST;
            case "LUNCH", "午餐" -> LUNCH;
            case "DINNER", "晚餐" -> DINNER;
            default -> throw new IllegalArgumentException("mealType 只支援 breakfast、lunch、dinner 或 早餐、午餐、晚餐");
        };
    }
}
