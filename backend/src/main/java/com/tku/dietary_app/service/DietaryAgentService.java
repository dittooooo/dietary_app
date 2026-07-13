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
        UserProfile user_profile = userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new RuntimeException("找不到使用者資料"));

        // 2. 撈近 7 天飲食紀錄
        LocalDateTime week_start = LocalDate.now().minusDays(6).atStartOfDay();
        LocalDateTime week_end = LocalDate.now().plusDays(1).atStartOfDay();
        List<DietRecord> records = dietRecordRepository.findByAdminFilters(
                userId, null, null, null, week_start, week_end);

        // 3. 組裝並回傳
        return buildPayload(request, user_profile, records);
    }

    private DietaryAgentPayload buildPayload(DietaryAskRequest request, UserProfile user_profile, List<DietRecord> records) {
        // healthConditions 存的是逗號分隔字串，例如 "高血壓,糖尿病"
        List<String> chronic_diseases = user_profile.getHealthConditions() != null && !user_profile.getHealthConditions().isBlank()
                ? Arrays.asList(user_profile.getHealthConditions().split(","))
                : List.of();

        List<DietRecordDto> diet_record_dtos = records.stream()
                .map(r -> DietRecordDto.builder()
                        .date(r.getCreatedAt().toLocalDate().toString())
                        .meal(r.getMealType().toLowerCase())
                        .dish_name(r.getDishName())
                        .note(r.getDescription())
                        .build())
                .toList();

        return DietaryAgentPayload.builder()
                .question(request.getQuestion())
                .question_type(request.getQuestionType())
                .dish_names(request.getDishNames())
                .user_profile(UserProfileDto.builder()
                        .height_cm(user_profile.getHeight())
                        .weight_kg(user_profile.getWeight())
                        .gender(user_profile.getGender())
                        .age(user_profile.getAge())
                        .goal(user_profile.getDietGoal())
                        .build())
                .health_condition(HealthConditionDto.builder()
                        .has_chronic_disease(!chronic_diseases.isEmpty())
                        .chronic_diseases(chronic_diseases)
                        .build())
                .weekly_diet_records(diet_record_dtos)
                .build();
    }
}
