package com.tku.dietary_app.dto;

import com.tku.dietary_app.entity.DietRecord;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDate;
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
    private Integer amount;
    private String photoUrl;
    private LocalDate date;
    private LocalDate mealDate;
    private LocalDateTime createdAt;
    private NutritionResponse nutrition;

    public static DietRecordResponse fromEntity(DietRecord dietRecord) {
        LocalDate recordDate = dietRecord.getMealDate() != null
                ? dietRecord.getMealDate()
                : (dietRecord.getDate() != null
                ? dietRecord.getDate()
                : (dietRecord.getCreatedAt() == null ? null : dietRecord.getCreatedAt().toLocalDate()));

        return DietRecordResponse.builder()
                .id(dietRecord.getId())
                .dishName(dietRecord.getDishName())
                .description(dietRecord.getDescription())
                .mealType(dietRecord.getMealType())
                .amount(dietRecord.getAmount())
                .photoUrl(dietRecord.getPhotoUrl())
                .date(recordDate)
                .mealDate(recordDate)
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
