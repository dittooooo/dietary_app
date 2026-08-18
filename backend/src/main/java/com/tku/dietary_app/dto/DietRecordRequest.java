package com.tku.dietary_app.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.time.LocalDate;

@Data
public class DietRecordRequest {
    @JsonProperty("dish_name")
    @JsonAlias({"dishName", "dish_name"})
    @Size(max = 255, message = "dishName 長度不可超過 255")
    private String dishName;

    @PositiveOrZero(message = "calories 必須大於或等於 0")
    private Double calories;

    @PositiveOrZero(message = "protein 必須大於或等於 0")
    private Double protein;

    @PositiveOrZero(message = "fat 必須大於或等於 0")
    private Double fat;

    @PositiveOrZero(message = "carbohydrates 必須大於或等於 0")
    private Double carbohydrates;

    @JsonProperty("record_date")
    @JsonAlias({"date", "record_date"})
    private LocalDate date;

    @Size(max = 1000, message = "description 長度不可超過 1000")
    private String description;

    @JsonProperty("meal_type")
    @JsonAlias({"mealType", "meal_type"})
    @Pattern(
            regexp = "^(?i:(BREAKFAST|LUNCH|DINNER))?$",
            message = "mealType 只允許 BREAKFAST、LUNCH、DINNER"
    )
    private String mealType;

    @Positive(message = "amount 必須大於 0")
    private Integer amount;
}
