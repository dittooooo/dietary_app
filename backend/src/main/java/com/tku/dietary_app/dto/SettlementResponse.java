package com.tku.dietary_app.dto;

import com.tku.dietary_app.entity.UserProfile;
import lombok.Builder;
import lombok.Data;

import java.time.LocalDate;
import java.util.List;

@Data
@Builder
public class SettlementResponse {
    private Boolean settled;
    private LocalDate lastSettleDate;
    private Integer bodyScore;
    private Integer muscleScore;
    private String bodyType;
    private String oldBodyType;
    private String newBodyType;
    private Boolean bodyTypeChanged;
    private Integer bodyScoreChange;
    private Integer muscleScoreChange;
    private Double recommendedCalories;
    private Double totalCalories;
    private Double recommendedProtein;
    private Double totalProtein;
    private List<DailySettlementResult> results;

    public static SettlementResponse fromResults(UserProfile profile,
                                                 Double recommendedProtein,
                                                 List<DailySettlementResult> results) {
        DailySettlementResult latestResult = results.isEmpty() ? null : results.get(results.size() - 1);
        DailySettlementResult latestTypeChange = results.stream()
                .filter(result -> Boolean.TRUE.equals(result.getBodyTypeChanged()))
                .reduce((first, second) -> second)
                .orElse(latestResult);

        return SettlementResponse.builder()
                .settled(!results.isEmpty())
                .lastSettleDate(profile.getLastSettleDate())
                .bodyScore(profile.getBodyScore())
                .muscleScore(profile.getMuscleScore())
                .bodyType(profile.getBodyType())
                .oldBodyType(latestTypeChange == null ? profile.getBodyType() : latestTypeChange.getOldBodyType())
                .newBodyType(profile.getBodyType())
                .bodyTypeChanged(results.stream().anyMatch(result -> Boolean.TRUE.equals(result.getBodyTypeChanged())))
                .bodyScoreChange(latestResult == null ? 0 : latestResult.getBodyScoreChange())
                .muscleScoreChange(latestResult == null ? 0 : latestResult.getMuscleScoreChange())
                .recommendedCalories(profile.getRecommendedCalories())
                .totalCalories(latestResult == null ? 0.0 : latestResult.getTotalCalories())
                .recommendedProtein(recommendedProtein)
                .totalProtein(latestResult == null ? 0.0 : latestResult.getTotalProtein())
                .results(results)
                .build();
    }
}
