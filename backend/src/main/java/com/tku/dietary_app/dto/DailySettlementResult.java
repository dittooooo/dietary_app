package com.tku.dietary_app.dto;

import lombok.Builder;
import lombok.Data;

import java.time.LocalDate;

@Data
@Builder
public class DailySettlementResult {
    private Boolean settled;
    private LocalDate recordDate;
    private String oldBodyType;
    private String newBodyType;
    private Boolean bodyTypeChanged;
    private Integer bodyScore;
    private Integer muscleScore;
    private Integer bodyScoreChange;
    private Integer muscleScoreChange;
    private Double recommendedCalories;
    private Double totalCalories;
    private Double recommendedProtein;
    private Double totalProtein;
}
