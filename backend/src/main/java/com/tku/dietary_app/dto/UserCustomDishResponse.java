package com.tku.dietary_app.dto;

import com.tku.dietary_app.entity.UserCustomDish;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserCustomDishResponse {
    private Long id;
    private String dishName;
    private Double calories;
    private Double protein;
    private Double fat;
    private Double carbohydrates;
    private String type;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public static UserCustomDishResponse fromEntity(UserCustomDish dish) {
        return UserCustomDishResponse.builder()
                .id(dish.getId())
                .dishName(dish.getDishName())
                .calories(dish.getCalories())
                .protein(dish.getProtein())
                .fat(dish.getFat())
                .carbohydrates(dish.getCarbohydrates())
                .type(dish.getType())
                .createdAt(dish.getCreatedAt())
                .updatedAt(dish.getUpdatedAt())
                .build();
    }
}
