package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.DietaryAgentPayload;
import com.tku.dietary_app.dto.DietaryAgentPayload.DietRecordDto;
import com.tku.dietary_app.dto.DietaryAgentPayload.HealthConditionDto;
import com.tku.dietary_app.dto.DietaryAgentPayload.UserProfileDto;
import com.tku.dietary_app.dto.DietaryAskRequest;
import com.tku.dietary_app.entity.DietRecord;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.repository.DietRecordRepository;
import com.tku.dietary_app.repository.UserProfileRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Arrays;
import java.util.List;

@Service
@RequiredArgsConstructor
public class DietaryAgentService {

    private final DietRecordRepository dietRecordRepository;
    private final UserProfileRepository userProfileRepository;

    public DietaryAgentPayload ask(Long userId, DietaryAskRequest request) {
        // 1. 撈 UserProfile
        UserProfile profile = userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new RuntimeException("找不到使用者資料"));

        // 2. 撈近 7 天飲食紀錄
        LocalDateTime weekStart = LocalDate.now().minusDays(6).atStartOfDay();
        LocalDateTime weekEnd = LocalDate.now().plusDays(1).atStartOfDay();
        List<DietRecord> records = dietRecordRepository.findByAdminFilters(
                userId, null, null, null, weekStart, weekEnd);

        // 3. 組裝並回傳
        return buildPayload(request, profile, records);
    }

    private DietaryAgentPayload buildPayload(DietaryAskRequest request, UserProfile profile, List<DietRecord> records) {
        // healthConditions 存的是逗號分隔字串，例如 "高血壓,糖尿病"
        List<String> diseases = profile.getHealthConditions() != null && !profile.getHealthConditions().isBlank()
                ? Arrays.asList(profile.getHealthConditions().split(","))
                : List.of();

        List<DietRecordDto> recordDtos = records.stream()
                .map(r -> DietRecordDto.builder()
                        .date(resolveMealDate(r).toString())
                        .meal(r.getMealType().toLowerCase())
                        .dishName(r.getDishName())
                        .description(r.getDescription())
                        .build())
                .toList();

        return DietaryAgentPayload.builder()
                .question(request.getQuestion())
                .userProfile(UserProfileDto.builder()
                        .heightCm(profile.getHeight())
                        .weightKg(profile.getWeight())
                        .gender(profile.getGender())
                        .age(profile.getAge())
                        .goal(profile.getDietGoal())
                        .build())
                .healthCondition(HealthConditionDto.builder()
                        .hasChronicDisease(!diseases.isEmpty())
                        .chronicDiseases(diseases)
                        .build())
                .weeklyDietRecords(recordDtos)
                .build();
    }

    private LocalDate resolveMealDate(DietRecord record) {
        if (record.getMealDate() != null) {
            return record.getMealDate();
        }
        return record.getCreatedAt().toLocalDate();
    }
}
