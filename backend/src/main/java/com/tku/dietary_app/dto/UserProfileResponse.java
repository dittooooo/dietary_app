package com.tku.dietary_app.dto;

import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.service.AgeCalculator;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserProfileResponse {
    private Long id;
    private Long userId;
    private String email;
    private String role;
    private Boolean enabled;
    private Boolean hasCompletedOnboarding;
    private String nickname;
    private String gender;
    private Integer age;
    private Double height;
    private Double weight;
    private List<String> healthConditions;
    private String dietGoal;
    private String petType;
    private String avatarUrl;
    private Double bmr;
    private Double tdee;
    private Double recommendedCalories;
    private Integer bodyScore;
    private Integer muscleScore;
    private String bodyType;
    private LocalDate lastSettleDate;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public static UserProfileResponse fromEntity(UserProfile profile) {
        return UserProfileResponse.builder()
                .id(profile.getId())
                .userId(profile.getUser() == null ? null : profile.getUser().getId())
                .email(profile.getUser() == null ? null : profile.getUser().getEmail())
                .role(profile.getUser() == null ? null : profile.getUser().getRole())
                .enabled(profile.getUser() == null ? null : profile.getUser().getEnabled())
                .hasCompletedOnboarding(profile.getUser() == null ? null : profile.getUser().getHasCompletedOnboarding())
                .nickname(profile.getNickname())
                .gender(profile.getGender())
                .age(AgeCalculator.calculateAge(profile.getBirthDate(), profile.getAge()))
                .height(profile.getHeight())
                .weight(profile.getWeight())
                .healthConditions(splitHealthConditions(profile.getHealthConditions()))
                .dietGoal(profile.getDietGoal())
                .petType(profile.getPetType())
                .avatarUrl(profile.getAvatarUrl())
                .bmr(profile.getBmr())
                .tdee(profile.getTdee())
                .recommendedCalories(profile.getRecommendedCalories())
                .bodyScore(profile.getBodyScore())
                .muscleScore(profile.getMuscleScore())
                .bodyType(profile.getBodyType())
                .lastSettleDate(profile.getLastSettleDate())
                .createdAt(profile.getCreatedAt())
                .updatedAt(profile.getUpdatedAt())
                .build();
    }

    private static List<String> splitHealthConditions(String healthConditions) {
        if (healthConditions == null || healthConditions.isBlank()) {
            return List.of();
        }

        return List.of(healthConditions.split(",")).stream()
                .map(String::trim)
                .filter(value -> !value.isBlank())
                .toList();
    }
}
