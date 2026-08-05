package com.tku.dietary_app.dto;

import com.tku.dietary_app.entity.UserProfile;
import lombok.Builder;
import lombok.Data;

import java.time.LocalDate;

@Data
@Builder
public class BodyStatusResponse {
    private Integer bodyScore;
    private Integer muscleScore;
    private String bodyType;
    private Double bmr;
    private Double tdee;
    private Double recommendedCalories;
    private Double recommendedProtein;
    private LocalDate lastSettleDate;

    public static BodyStatusResponse fromProfile(UserProfile profile, Double recommendedProtein) {
        return BodyStatusResponse.builder()
                .bodyScore(profile.getBodyScore())
                .muscleScore(profile.getMuscleScore())
                .bodyType(profile.getBodyType())
                .bmr(profile.getBmr())
                .tdee(profile.getTdee())
                .recommendedCalories(profile.getRecommendedCalories())
                .recommendedProtein(recommendedProtein)
                .lastSettleDate(profile.getLastSettleDate())
                .build();
    }
}
