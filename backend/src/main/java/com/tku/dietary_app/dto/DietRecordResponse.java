package com.tku.dietary_app.dto;

import com.tku.dietary_app.entity.DietRecord;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DietRecordResponse {
    private Long id;
    private String dishName;
    private String description;
    private String mealType;
    private String photoUrl;
    private LocalDateTime createdAt;
    private NutritionResponse nutrition;

    public static DietRecordResponse fromEntity(DietRecord dietRecord) {
        return DietRecordResponse.builder()
                .id(dietRecord.getId())
                .dishName(dietRecord.getDishName())
                .description(dietRecord.getDescription())
                .mealType(dietRecord.getMealType())
                .photoUrl(dietRecord.getPhotoUrl())
                .createdAt(dietRecord.getCreatedAt())
                .nutrition(NutritionResponse.fromDietRecord(
                        dietRecord.getCalories(),
                        dietRecord.getProtein(),
                        dietRecord.getFat(),
                        dietRecord.getCarbohydrates()
                ))
                .build();
    }
}
