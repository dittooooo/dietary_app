package com.tku.dietary_app.dto;

import lombok.Data;

@Data
public class MenuItemRequest {
    private String restaurantName;
    private String dishName;
    private String ingredients;
    private Double calories;
    private Double protein;
    private Double fat;
    private Double carbohydrates;
    private String recommendLevel;
}
