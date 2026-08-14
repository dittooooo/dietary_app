package com.tku.dietary_app.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class NutritionResponse {
    private String calories;      // 熱量 (kcal)
    private String protein;       // 蛋白質 (g)
    private String fat;           // 脂肪 (g)
    private String carbohydrates; // 碳水化合物 (g)

    public static NutritionResponse fromDietRecord(Double calories, Double protein, Double fat, Double carbohydrates) {
        return NutritionResponse.builder()
                .calories(calories != null ? calories + " kcal" : null)
                .protein(protein != null ? protein + " g" : null)
                .fat(fat != null ? fat + " g" : null)
                .carbohydrates(carbohydrates != null ? carbohydrates + " g" : null)
                .build();
    }
}
