package com.tku.dietary_app.entity;

import java.util.Locale;

public enum MealType {
    BREAKFAST,
    LUNCH,
    DINNER,
    OTHER;

    public static MealType from(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }

        return switch (value.trim().toUpperCase(Locale.ROOT)) {
            case "BREAKFAST", "早餐" -> BREAKFAST;
            case "LUNCH", "午餐" -> LUNCH;
            case "DINNER", "晚餐" -> DINNER;
            case "OTHER", "其他" -> OTHER;
            default -> throw new IllegalArgumentException("mealType 只支援 breakfast、lunch、dinner、other 或 早餐、午餐、晚餐、其他");
        };
    }
}
