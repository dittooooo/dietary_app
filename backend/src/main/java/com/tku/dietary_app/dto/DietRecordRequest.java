package com.tku.dietary_app.dto;

import lombok.Data;

@Data
public class DietRecordRequest {
    private String dishName;
    private String nutrition;
    private String description;
    private String mealType;
}
