package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.BodyStatusResponse;
import com.tku.dietary_app.dto.DailySettlementResult;
import com.tku.dietary_app.dto.SettlementResponse;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.exception.ResourceNotFoundException;
import com.tku.dietary_app.repository.DietRecordRepository;
import com.tku.dietary_app.repository.UserProfileRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

@Service
@RequiredArgsConstructor
public class BodyStatusService {
    private final UserProfileRepository userProfileRepository;
    private final DietRecordRepository dietRecordRepository;
    private final BodyMetricsService bodyMetricsService;
    private final Clock taipeiClock;

    @Transactional(readOnly = true)
    public BodyStatusResponse getCurrentStatus(Long userId) {
        UserProfile profile = getProfile(userId);
        ensureMetrics(profile);
        return BodyStatusResponse.fromProfile(profile, bodyMetricsService.calculateRecommendedProtein(profile));
    }

    @Transactional
    public SettlementResponse settleDailyScores(Long userId) {
        UserProfile profile = userProfileRepository.findByUserIdForUpdate(userId)
                .orElseThrow(() -> new ResourceNotFoundException("找不到使用者個人資料，無法進行每日結算"));
        ensureMetrics(profile);

        if (isAdminProfile(profile)) {
            return SettlementResponse.fromResults(profile, bodyMetricsService.calculateRecommendedProtein(profile), List.of());
        }

        LocalDate yesterday = LocalDate.now(taipeiClock).minusDays(1);
        LocalDate startDate = determineFirstUnsettledDate(profile, yesterday);
        List<DailySettlementResult> results = new ArrayList<>();

        if (startDate == null) {
            return SettlementResponse.fromResults(profile, bodyMetricsService.calculateRecommendedProtein(profile), results);
        }

        LocalDate recordDate = startDate;
        while (!recordDate.isAfter(yesterday)) {
            results.add(settleOneDate(profile, recordDate));
            profile.setLastSettleDate(recordDate);
            recordDate = recordDate.plusDays(1);
        }

        userProfileRepository.save(profile);
        return SettlementResponse.fromResults(profile, bodyMetricsService.calculateRecommendedProtein(profile), results);
    }

    @Transactional
    public BodyStatusResponse recalculateBodyMetrics(Long userId) {
        UserProfile profile = userProfileRepository.findByUserIdForUpdate(userId)
                .orElseThrow(() -> new ResourceNotFoundException("找不到使用者個人資料，無法重算身體指標"));
        bodyMetricsService.recalculateAndApply(profile);
        userProfileRepository.save(profile);
        return BodyStatusResponse.fromProfile(profile, bodyMetricsService.calculateRecommendedProtein(profile));
    }

    private DailySettlementResult settleOneDate(UserProfile profile, LocalDate recordDate) {
        DietRecordRepository.DailyNutritionSummary summary =
                dietRecordRepository.summarizeByUserAndRecordDate(profile.getUser().getId(), recordDate);

        long recordCount = summary == null || summary.getRecordCount() == null ? 0L : summary.getRecordCount();
        double totalCalories = summary == null || summary.getTotalCalories() == null ? 0.0 : summary.getTotalCalories();
        double totalProtein = summary == null || summary.getTotalProtein() == null ? 0.0 : summary.getTotalProtein();
        boolean hasDietRecords = recordCount > 0;

        double recommendedCalories = profile.getRecommendedCalories();
        double recommendedProtein = bodyMetricsService.calculateRecommendedProtein(profile);
        int bodyScoreChange = bodyMetricsService.calculateBodyScoreChange(hasDietRecords, totalCalories - recommendedCalories);
        double proteinRate = totalProtein / recommendedProtein * 100;
        int muscleScoreChange = bodyMetricsService.calculateMuscleScoreChange(hasDietRecords, proteinRate);

        String oldBodyType = normalizeBodyType(profile.getBodyType());
        int newBodyScore = bodyMetricsService.clampScore(profile.getBodyScore() + bodyScoreChange);
        int newMuscleScore = bodyMetricsService.clampScore(profile.getMuscleScore() + muscleScoreChange);
        String newBodyType = bodyMetricsService.determineBodyType(newBodyScore, newMuscleScore);

        profile.setBodyScore(newBodyScore);
        profile.setMuscleScore(newMuscleScore);
        profile.setBodyType(newBodyType);

        return DailySettlementResult.builder()
                .settled(true)
                .recordDate(recordDate)
                .oldBodyType(oldBodyType)
                .newBodyType(newBodyType)
                .bodyTypeChanged(!oldBodyType.equals(newBodyType))
                .bodyScore(newBodyScore)
                .muscleScore(newMuscleScore)
                .bodyScoreChange(bodyScoreChange)
                .muscleScoreChange(muscleScoreChange)
                .recommendedCalories(recommendedCalories)
                .totalCalories(totalCalories)
                .recommendedProtein(recommendedProtein)
                .totalProtein(totalProtein)
                .build();
    }

    private LocalDate determineFirstUnsettledDate(UserProfile profile, LocalDate yesterday) {
        LocalDate lastSettleDate = profile.getLastSettleDate();
        if (lastSettleDate != null) {
            LocalDate startDate = lastSettleDate.plusDays(1);
            return startDate.isAfter(yesterday) ? null : startDate;
        }

        LocalDate createdDate = profile.getCreatedAt() == null
                ? LocalDate.now(taipeiClock)
                : profile.getCreatedAt().toLocalDate();
        LocalDate startDate = createdDate.isBefore(yesterday) ? yesterday : createdDate;
        return startDate.isAfter(yesterday) ? null : startDate;
    }

    private UserProfile getProfile(Long userId) {
        return userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new ResourceNotFoundException("找不到使用者個人資料"));
    }

    private void ensureMetrics(UserProfile profile) {
        if (profile.getBodyScore() == null) {
            profile.setBodyScore(50);
        }
        if (profile.getMuscleScore() == null) {
            profile.setMuscleScore(50);
        }
        profile.setBodyType(normalizeBodyType(profile.getBodyType()));
        if (profile.getBmr() == null || profile.getTdee() == null || profile.getRecommendedCalories() == null) {
            bodyMetricsService.recalculateAndApply(profile);
        }
    }

    private boolean isAdminProfile(UserProfile profile) {
        String role = profile.getUser() == null ? "" : profile.getUser().getRole();
        return role != null && ("ROLE_ADMIN".equalsIgnoreCase(role) || "ADMIN".equalsIgnoreCase(role));
    }

    private String normalizeBodyType(String bodyType) {
        if (bodyType == null || bodyType.isBlank() || "STANDARD".equalsIgnoreCase(bodyType)) {
            return BodyMetricsService.BODY_TYPE_NORMAL;
        }
        return bodyType;
    }
}
