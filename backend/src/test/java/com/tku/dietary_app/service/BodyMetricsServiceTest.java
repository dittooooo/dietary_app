package com.tku.dietary_app.service;

import com.tku.dietary_app.entity.UserProfile;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;

class BodyMetricsServiceTest {
    private final BodyMetricsService service = new BodyMetricsService();

    @Test
    void recalculatesBmrTdeeAndRecommendedCaloriesByMdRules() {
        UserProfile profile = UserProfile.builder()
                .gender("男")
                .age(30)
                .height(170.0)
                .weight(70.0)
                .bodyScore(50)
                .muscleScore(50)
                .build();

        service.recalculateAndApply(profile);

        assertThat(profile.getBmr()).isEqualTo(1617.5);
        assertThat(profile.getTdee()).isEqualTo(2224.0625);
        assertThat(profile.getRecommendedCalories()).isEqualTo(2224.0625);
        assertThat(profile.getBodyScore()).isEqualTo(50);
        assertThat(profile.getMuscleScore()).isEqualTo(50);
        assertThat(profile.getBodyType()).isEqualTo("NORMAL");
    }

    @Test
    void bodyScoreFrom50Plus10Becomes60() {
        int change = service.calculateBodyScoreChange(true, 700);

        assertThat(service.clampScore(50 + change)).isEqualTo(60);
    }

    @Test
    void scoreIsClampedBetween0And100() {
        assertThat(service.clampScore(95 + 10)).isEqualTo(100);
        assertThat(service.clampScore(5 - 10)).isEqualTo(0);
    }

    @ParameterizedTest
    @CsvSource({
            "700,10",
            "500,5",
            "300,3",
            "299,0",
            "-299,0",
            "-300,-3",
            "-500,-5",
            "-700,-10"
    })
    void bodyScoreChangeIntervals(double calorieDifference, int expectedChange) {
        assertThat(service.calculateBodyScoreChange(true, calorieDifference)).isEqualTo(expectedChange);
    }

    @Test
    void noDietRecordsDeductsBothScoresBy10() {
        assertThat(service.calculateBodyScoreChange(false, 0)).isEqualTo(-10);
        assertThat(service.calculateMuscleScoreChange(false, 0)).isEqualTo(-10);
    }

    @ParameterizedTest
    @CsvSource({
            "120,10",
            "100,5",
            "80,3",
            "60,0",
            "40,-3",
            "39.99,-5"
    })
    void muscleScoreChangeIntervals(double proteinRate, int expectedChange) {
        assertThat(service.calculateMuscleScoreChange(true, proteinRate)).isEqualTo(expectedChange);
    }

    @Test
    void bodyTypeFollowsMdPriority() {
        assertThat(service.determineBodyType(70, 100)).isEqualTo("FAT");
        assertThat(service.determineBodyType(69, 70)).isEqualTo("MUSCULAR");
        assertThat(service.determineBodyType(30, 69)).isEqualTo("THIN");
        assertThat(service.determineBodyType(31, 69)).isEqualTo("NORMAL");
    }
}
