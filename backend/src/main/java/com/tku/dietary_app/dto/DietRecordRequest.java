package com.tku.dietary_app.dto;

import lombok.Data;

@Data
public class DietRecordRequest {
    private String dishName;
    private Double calories;
    private Double protein;
    private Double fat;
    private Double carbohydrates;
    private String description;
    private String mealType;
}
