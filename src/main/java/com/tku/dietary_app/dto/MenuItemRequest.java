package com.tku.dietary_app.dto;

import lombok.Data;

@Data
public class MenuItemRequest {
    private String restaurantName;
    private String dishName;
    private String ingredients;
    private String nutrition;
    private String recommendLevel;
}
