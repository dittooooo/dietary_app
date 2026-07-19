package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.DietaryAgentPayload;
import com.tku.dietary_app.dto.DietaryAgentPayload.UserProfileDto;
import com.tku.dietary_app.dto.DietaryAskRequest;
import com.tku.dietary_app.dto.DietaryDishNutritionRequest;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.repository.UserProfileRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.Arrays;
import java.util.List;

@Service
@RequiredArgsConstructor
public class DietaryAgentService {

    private final UserProfileRepository userProfileRepository;
    private final RestTemplate restTemplate;

    @Value("${app.partner.dietary.base-url:}")
    private String partnerApiBaseUrl;

    @Value("${app.partner.dietary.ask-path:/ask}")
    private String partnerApiAskPath;

    @Value("${app.partner.dietary.dish-nutrition-path:/dish-nutrition}")
    private String partnerApiDishNutritionPath;

    public Object ask(Long userId, DietaryAskRequest request) {
        // 1. 撈 UserProfile
        UserProfile user_profile = userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new RuntimeException("找不到使用者資料"));

        DietaryAgentPayload payload = buildPayload(request, user_profile);
        return callPartnerApi(partnerApiAskPath, payload);
    }

    public Object dishNutrition(DietaryDishNutritionRequest request) {
        return callPartnerApi(partnerApiDishNutritionPath, request);
    }

    private DietaryAgentPayload buildPayload(DietaryAskRequest request, UserProfile user_profile) {
        return DietaryAgentPayload.builder()
                .question(request.getQuestion())
                .question_type(request.getQuestionType())
                .dish_names(request.getDishNames())
                .user_profile(UserProfileDto.builder()
                        .height_cm(user_profile.getHeight())
                        .weight_kg(user_profile.getWeight())
                        .gender(user_profile.getGender())
                        .age(user_profile.getAge())
                        .recommended_calorie(calculateRecommendedCalorie(user_profile))
                        .build())
                .build();
    }

    private Integer calculateRecommendedCalorie(UserProfile user_profile) {
        double bmr;
        if ("女".equals(user_profile.getGender())) {
            bmr = 10 * user_profile.getWeight() + 6.25 * user_profile.getHeight() - 5 * user_profile.getAge() - 161;
        } else {
            bmr = 10 * user_profile.getWeight() + 6.25 * user_profile.getHeight() - 5 * user_profile.getAge() + 5;
        }

        String diet_goal = user_profile.getDietGoal() == null ? "" : user_profile.getDietGoal();
        if (diet_goal.contains("增肌") || diet_goal.contains("增重")) {
            bmr += 200;
        } else if (diet_goal.contains("減脂") || diet_goal.contains("減重")) {
            bmr -= 300;
        }

        return (int) Math.round(bmr);
    }

    private Object callPartnerApi(String apiPath, Object payload) {
        if (partnerApiBaseUrl == null || partnerApiBaseUrl.isBlank()) {
            throw new IllegalStateException("尚未設定組員 API 網址");
        }
        if (apiPath == null || apiPath.isBlank()) {
            throw new IllegalStateException("尚未設定組員 API 路徑");
        }

        String url = partnerApiBaseUrl.endsWith("/")
                ? partnerApiBaseUrl.substring(0, partnerApiBaseUrl.length() - 1) + apiPath
                : partnerApiBaseUrl + apiPath;

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        HttpEntity<Object> requestEntity = new HttpEntity<>(payload, headers);
        return restTemplate.postForObject(url, requestEntity, Object.class);
    }
}
