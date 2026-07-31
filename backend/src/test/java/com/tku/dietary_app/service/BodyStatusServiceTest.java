package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.SettlementResponse;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.repository.DietRecordRepository;
import com.tku.dietary_app.repository.UserProfileRepository;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class BodyStatusServiceTest {
    private static final ZoneId TAIPEI = ZoneId.of("Asia/Taipei");
    private final UserProfileRepository userProfileRepository = mock(UserProfileRepository.class);
    private final DietRecordRepository dietRecordRepository = mock(DietRecordRepository.class);
    private final BodyMetricsService bodyMetricsService = new BodyMetricsService();
    private final Clock clock = Clock.fixed(Instant.parse("2026-07-31T01:00:00Z"), TAIPEI);
    private final BodyStatusService service = new BodyStatusService(
            userProfileRepository,
            dietRecordRepository,
            bodyMetricsService,
            clock
    );

    @Test
    void repeatedSettlementDoesNotApplyScoreTwiceForSameDate() {
        UserProfile profile = profileWithScores(50, 50, LocalDate.of(2026, 7, 29));
        when(userProfileRepository.findByUserIdForUpdate(1L)).thenReturn(Optional.of(profile));
        when(dietRecordRepository.summarizeByUserAndCreatedAtRange(
                eq(1L),
                eq(LocalDateTime.of(2026, 7, 30, 0, 0)),
                eq(LocalDateTime.of(2026, 7, 31, 0, 0))
        )).thenReturn(summary(1L, 2950.0, 84.0));

        SettlementResponse first = service.settleDailyScores(1L);
        SettlementResponse second = service.settleDailyScores(1L);

        assertThat(first.getSettled()).isTrue();
        assertThat(first.getBodyScore()).isEqualTo(60);
        assertThat(second.getSettled()).isFalse();
        assertThat(second.getResults()).isEmpty();
        assertThat(profile.getBodyScore()).isEqualTo(60);
        assertThat(profile.getLastSettleDate()).isEqualTo(LocalDate.of(2026, 7, 30));
    }

    @Test
    void alreadySettledDateIsNotRecalculatedAfterBackfilledDietRecord() {
        UserProfile profile = profileWithScores(60, 55, LocalDate.of(2026, 7, 30));
        when(userProfileRepository.findByUserIdForUpdate(1L)).thenReturn(Optional.of(profile));

        SettlementResponse response = service.settleDailyScores(1L);

        assertThat(response.getSettled()).isFalse();
        assertThat(profile.getBodyScore()).isEqualTo(60);
        assertThat(profile.getMuscleScore()).isEqualTo(55);
        verify(dietRecordRepository, never()).summarizeByUserAndCreatedAtRange(any(), any(), any());
    }

    private UserProfile profileWithScores(int bodyScore, int muscleScore, LocalDate lastSettleDate) {
        User user = User.builder().id(1L).email("user@example.com").password("encoded").build();
        UserProfile profile = UserProfile.builder()
                .id(10L)
                .user(user)
                .nickname("Tester")
                .gender("男")
                .age(30)
                .height(170.0)
                .weight(70.0)
                .healthConditions("None")
                .dietGoal("Maintain")
                .petType("cat")
                .bmr(1617.5)
                .tdee(2224.0625)
                .recommendedCalories(2224.0625)
                .bodyScore(bodyScore)
                .muscleScore(muscleScore)
                .bodyType("NORMAL")
                .lastSettleDate(lastSettleDate)
                .build();
        profile.setCreatedAt(LocalDateTime.of(2026, 7, 20, 12, 0));
        return profile;
    }

    private DietRecordRepository.DailyNutritionSummary summary(Long count, Double calories, Double protein) {
        return new DietRecordRepository.DailyNutritionSummary() {
            @Override
            public Long getRecordCount() {
                return count;
            }

            @Override
            public Double getTotalCalories() {
                return calories;
            }

            @Override
            public Double getTotalProtein() {
                return protein;
            }
        };
    }
}
