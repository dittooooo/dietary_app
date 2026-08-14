package com.tku.dietary_app.service;

import com.tku.dietary_app.entity.UserProfile;
import org.springframework.stereotype.Service;

@Service
public class BodyMetricsService {
    public static final String BODY_TYPE_THIN = "THIN";
    public static final String BODY_TYPE_NORMAL = "NORMAL";
    public static final String BODY_TYPE_MUSCULAR = "MUSCULAR";
    public static final String BODY_TYPE_FAT = "FAT";

    private static final double ACTIVITY_FACTOR = 1.375;
    private static final double RECOMMENDED_PROTEIN_PER_KG = 1.2;

    public void recalculateAndApply(UserProfile profile) {
        validateRequiredProfileData(profile);

        double bmr = calculateBmr(profile.getGender(), profile.getWeight(), profile.getHeight(), profile.getAge());
        double tdee = bmr * ACTIVITY_FACTOR;

        profile.setBmr(bmr);
        profile.setTdee(tdee);
        profile.setRecommendedCalories(tdee);

        if (profile.getBodyScore() == null) {
            profile.setBodyScore(50);
        }
        if (profile.getMuscleScore() == null) {
            profile.setMuscleScore(50);
        }
        profile.setBodyType(determineBodyType(profile.getBodyScore(), profile.getMuscleScore()));
    }

    public double calculateBmr(String gender, Double weightKg, Double heightCm, Integer age) {
        String normalizedGender = normalizeGender(gender);
        if (weightKg == null || weightKg <= 0) {
            throw new IllegalArgumentException("使用者體重資料不足，無法計算 BMR");
        }
        if (heightCm == null || heightCm <= 0) {
            throw new IllegalArgumentException("使用者身高資料不足，無法計算 BMR");
        }
        if (age == null || age <= 0) {
            throw new IllegalArgumentException("使用者年齡資料不足，無法計算 BMR");
        }

        double base = 10 * weightKg + 6.25 * heightCm - 5 * age;
        return "FEMALE".equals(normalizedGender) ? base - 161 : base + 5;
    }

    public double calculateRecommendedProtein(UserProfile profile) {
        if (profile == null || profile.getWeight() == null || profile.getWeight() <= 0) {
            throw new IllegalArgumentException("使用者體重資料不足，無法計算每日建議蛋白質");
        }
        return profile.getWeight() * RECOMMENDED_PROTEIN_PER_KG;
    }

    public int calculateBodyScoreChange(boolean hasDietRecords, double calorieDifference) {
        if (!hasDietRecords) {
            return -10;
        }
        if (calorieDifference >= 700) {
            return 10;
        }
        if (calorieDifference >= 500) {
            return 5;
        }
        if (calorieDifference >= 300) {
            return 3;
        }
        if (calorieDifference <= -700) {
            return -10;
        }
        if (calorieDifference <= -500) {
            return -5;
        }
        if (calorieDifference <= -300) {
            return -3;
        }
        return 0;
    }

    public int calculateMuscleScoreChange(boolean hasDietRecords, double proteinRate) {
        if (!hasDietRecords) {
            return -10;
        }
        if (proteinRate >= 120) {
            return 10;
        }
        if (proteinRate >= 100) {
            return 5;
        }
        if (proteinRate >= 80) {
            return 3;
        }
        if (proteinRate >= 60) {
            return 0;
        }
        if (proteinRate >= 40) {
            return -3;
        }
        return -5;
    }

    public int clampScore(int score) {
        return Math.max(0, Math.min(100, score));
    }

    public String determineBodyType(Integer bodyScore, Integer muscleScore) {
        int currentBodyScore = bodyScore == null ? 50 : bodyScore;
        int currentMuscleScore = muscleScore == null ? 50 : muscleScore;

        if (currentBodyScore >= 70) {
            return BODY_TYPE_FAT;
        }
        if (currentMuscleScore >= 70) {
            return BODY_TYPE_MUSCULAR;
        }
        if (currentBodyScore <= 30) {
            return BODY_TYPE_THIN;
        }
        return BODY_TYPE_NORMAL;
    }

    private void validateRequiredProfileData(UserProfile profile) {
        if (profile == null) {
            throw new IllegalArgumentException("找不到使用者個人資料，無法計算身體數據");
        }
        calculateBmr(profile.getGender(), profile.getWeight(), profile.getHeight(), profile.getAge());
    }

    private String normalizeGender(String gender) {
        if (gender == null || gender.isBlank()) {
            throw new IllegalArgumentException("使用者性別資料不足，無法計算 BMR");
        }

        String normalized = gender.trim().toLowerCase();
        if (normalized.equals("女") || normalized.equals("女性") || normalized.equals("female") || normalized.equals("f")) {
            return "FEMALE";
        }
        if (normalized.equals("男") || normalized.equals("男性") || normalized.equals("male") || normalized.equals("m")) {
            return "MALE";
        }
        throw new IllegalArgumentException("使用者性別資料無法辨識，無法計算 BMR");
    }
}
