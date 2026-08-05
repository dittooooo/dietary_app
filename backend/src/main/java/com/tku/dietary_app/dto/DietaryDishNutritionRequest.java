package com.tku.dietary_app.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class DietaryDishNutritionRequest {
    @JsonProperty("dish_name")
    @NotBlank(message = "dish_name 為必填")
    private String dishName;
}
