package com.tku.dietary_app.dto;

import com.tku.dietary_app.entity.MenuItem;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MenuItemResponse {
    private Long id;
    private String restaurantName;
    private String dishName;
    private String ingredients;
    private NutritionResponse nutrition;
    private String recommendLevel;

    public static MenuItemResponse fromEntity(MenuItem menuItem) {
        return MenuItemResponse.builder()
                .id(menuItem.getId())
                .restaurantName(menuItem.getRestaurantName())
                .dishName(menuItem.getDishName())
                .ingredients(menuItem.getIngredients())
                .nutrition(NutritionResponse.fromMenuItem(
                        menuItem.getCalories(),
                        menuItem.getProtein(),
                        menuItem.getFat(),
                        menuItem.getCarbohydrates()
                ))
                .recommendLevel(menuItem.getRecommendLevel())
                .build();
    }
}
