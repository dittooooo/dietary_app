package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.DietaryAgentPayload;
import com.tku.dietary_app.dto.DietaryAgentPayload.HealthConditionDto;
import com.tku.dietary_app.dto.DietaryAgentPayload.UserProfileDto;
import com.tku.dietary_app.dto.DietaryAgentPayload.WeeklyDietRecordDto;
import com.tku.dietary_app.dto.DietaryAskRequest;
import com.tku.dietary_app.dto.DietaryDishNutritionRequest;
import com.tku.dietary_app.entity.DietRecord;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.repository.DietRecordRepository;
import com.tku.dietary_app.repository.UserProfileRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class DietaryAgentService {
    private static final Pattern NUMBER_PATTERN = Pattern.compile("-?\\d+(\\.\\d+)?");

    private static final String[] CALORIES_KEYS = {"calories", "calorie", "kcal", "熱量"};
    private static final String[] PROTEIN_KEYS = {"protein", "proteins", "蛋白質"};
    private static final String[] FAT_KEYS = {"fat", "脂肪"};
    private static final String[] CARBOHYDRATES_KEYS = {"carbohydrates", "carbohydrate", "carbs", "carb", "碳水化合物", "碳水"};

    private final DietRecordRepository dietRecordRepository;
    private final UserProfileRepository userProfileRepository;
    private final RestTemplate restTemplate;

    @Value("${app.partner.dietary.base-url:}")
    private String partnerApiBaseUrl;

    @Value("${app.partner.dietary.ask-path:/ask}")
    private String partnerApiAskPath;

    @Value("${app.partner.dietary.dish-nutrition-path:/dish-nutrition}")
    private String partnerApiDishNutritionPath;

    public Object ask(Long userId, DietaryAskRequest request) {
        UserProfile user_profile = userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new RuntimeException("找不到使用者資料"));

        DietaryAgentPayload payload = buildPayload(userId, request, user_profile);
        return callPartnerApi(partnerApiAskPath, payload);
    }

    public Object dishNutrition(DietaryDishNutritionRequest request) {
        return callPartnerApi(partnerApiDishNutritionPath, request);
    }

    public NutritionValues fetchDishNutrition(String dishName) {
        if (dishName == null || dishName.isBlank()) {
            throw new IllegalArgumentException("dishName 為必填");
        }

        DietaryDishNutritionRequest request = new DietaryDishNutritionRequest();
        request.setDishName(dishName.trim());
        Object response = dishNutrition(request);

        return parseNutritionValues(response);
    }

    private DietaryAgentPayload buildPayload(Long userId, DietaryAskRequest request, UserProfile user_profile) {
        DietaryAgentPayload.UserProfileDto userProfileDto = request.getUserProfile() != null
                ? DietaryAgentPayload.UserProfileDto.builder()
                .heightCm(request.getUserProfile().getHeightCm())
                .weightKg(request.getUserProfile().getWeightKg())
                .gender(request.getUserProfile().getGender())
                .age(request.getUserProfile().getAge())
                .build()
                : DietaryAgentPayload.UserProfileDto.builder()
                .heightCm(user_profile.getHeight())
                .weightKg(user_profile.getWeight())
                .gender(user_profile.getGender())
                .age(user_profile.getAge())
                .build();

        HealthConditionDto healthConditionDto = request.getHealthCondition() != null
                ? DietaryAgentPayload.HealthConditionDto.builder()
                .hasChronicDisease(request.getHealthCondition().getHasChronicDisease())
                .chronicDiseases(request.getHealthCondition().getChronicDiseases())
                .build()
                : buildHealthConditionDto(user_profile);

        List<WeeklyDietRecordDto> weeklyDietRecords = request.getWeeklyDietRecords() != null
                ? request.getWeeklyDietRecords().stream()
                .map(record -> DietaryAgentPayload.WeeklyDietRecordDto.builder()
                        .date(record.getDate())
                        .meal(record.getMeal())
                        .dishName(record.getDishName())
                        .note(record.getNote())
                        .build())
                .collect(Collectors.toList())
                : fetchWeeklyDietRecords(userId);

        return DietaryAgentPayload.builder()
                .question(request.getQuestion())
                .questionType(request.getQuestionType())
                .dishNames(request.getDishNames())
                .userProfile(userProfileDto)
                .healthCondition(healthConditionDto)
                .weeklyDietRecords(weeklyDietRecords)
                .build();
    }

    private HealthConditionDto buildHealthConditionDto(UserProfile user_profile) {
        List<String> chronicDiseases = parseHealthConditions(user_profile.getHealthConditions());
        return HealthConditionDto.builder()
                .hasChronicDisease(!chronicDiseases.isEmpty())
                .chronicDiseases(chronicDiseases)
                .build();
    }

    private List<WeeklyDietRecordDto> fetchWeeklyDietRecords(Long userId) {
        LocalDateTime startAt = LocalDate.now().minusDays(7).atStartOfDay();
        List<DietRecord> records = dietRecordRepository
                .findByUserIdAndCreatedAtGreaterThanEqualOrderByCreatedAtDescIdDesc(userId, startAt);

        return records.stream()
                .map(record -> DietaryAgentPayload.WeeklyDietRecordDto.builder()
                        .date(record.getDate() != null
                                ? record.getDate()
                                : (record.getCreatedAt() == null ? null : record.getCreatedAt().toLocalDate()))
                        .meal(record.getMealType())
                        .dishName(record.getDishName())
                        .note(record.getDescription())
                        .build())
                .collect(Collectors.toList());
    }

    private List<String> parseHealthConditions(String healthConditions) {
        if (healthConditions == null || healthConditions.isBlank()) {
            return List.of();
        }

        return List.of(healthConditions.split(",")).stream()
                .map(String::trim)
                .filter(value -> !value.isBlank())
                .collect(Collectors.toList());
    }

    private Integer calculateRecommendedCalorie(UserProfile user_profile) {
        // 如果資料庫已經有計算好的建議熱量，就直接使用
        if (user_profile.getRecommendedCalories() != null) {
            return (int) Math.round(user_profile.getRecommendedCalories());
        }

        double bmr;
        if ("女".equals(user_profile.getGender())) {
            bmr = 10 * user_profile.getWeight()
                    + 6.25 * user_profile.getHeight()
                    - 5 * user_profile.getAge()
                    - 161;
        } else {
            bmr = 10 * user_profile.getWeight()
                    + 6.25 * user_profile.getHeight()
                    - 5 * user_profile.getAge()
                    + 5;
        }

        String diet_goal = user_profile.getDietGoal() == null
                ? ""
                : user_profile.getDietGoal();

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

    private NutritionValues parseNutritionValues(Object response) {
        if (!(response instanceof Map<?, ?> rootMap)) {
            throw new RuntimeException("組員 dish-nutrition 回傳格式錯誤，無法解析營養成分");
        }

        List<Map<?, ?>> candidateMaps = collectCandidateMaps(rootMap);

        NutritionValues bestMatch = null;
        int bestScore = 0;

        for (Map<?, ?> candidate : candidateMaps) {
            NutritionValues parsed = new NutritionValues(
                    extractNumber(candidate, CALORIES_KEYS),
                    extractNumber(candidate, PROTEIN_KEYS),
                    extractNumber(candidate, FAT_KEYS),
                    extractNumber(candidate, CARBOHYDRATES_KEYS)
            );

            int score = countPresent(parsed);
            if (score > bestScore) {
                bestScore = score;
                bestMatch = parsed;
            }
        }

        NutritionValues nutrientsArrayMatch = extractFromNutrientsArray(rootMap);
        int nutrientsArrayScore = countPresent(nutrientsArrayMatch);
        if (nutrientsArrayScore > bestScore) {
            bestScore = nutrientsArrayScore;
            bestMatch = nutrientsArrayMatch;
        }

        if (bestMatch == null) {
            return new NutritionValues(null, null, null, null);
        }

        return bestMatch;
    }

    private NutritionValues extractFromNutrientsArray(Map<?, ?> rootMap) {
        Object dishNutrition = findValueIgnoreCase(rootMap, "dish_nutrition");
        if (!(dishNutrition instanceof Map<?, ?> dishNutritionMap)) {
            return new NutritionValues(null, null, null, null);
        }

        Object nutrients = findValueIgnoreCase(dishNutritionMap, "nutrients");
        if (!(nutrients instanceof List<?> nutrientsList)) {
            return new NutritionValues(null, null, null, null);
        }

        Double calories = null;
        Double protein = null;
        Double fat = null;
        Double carbohydrates = null;

        for (Object item : nutrientsList) {
            if (!(item instanceof Map<?, ?> nutrientMap)) {
                continue;
            }

            Object nutrientNameObject = findValueIgnoreCase(nutrientMap, "name");
            if (!(nutrientNameObject instanceof String nutrientName)) {
                continue;
            }

            Double amount = parseNumber(findValueIgnoreCase(nutrientMap, "amount_per_serving"));
            if (amount == null) {
                continue;
            }

            if (matchesAnyKey(nutrientName, CALORIES_KEYS)) {
                calories = amount;
            } else if (matchesAnyKey(nutrientName, PROTEIN_KEYS)) {
                protein = amount;
            } else if (matchesAnyKey(nutrientName, FAT_KEYS)) {
                fat = amount;
            } else if (matchesAnyKey(nutrientName, CARBOHYDRATES_KEYS)) {
                carbohydrates = amount;
            }
        }

        return new NutritionValues(calories, protein, fat, carbohydrates);
    }

    private List<Map<?, ?>> collectCandidateMaps(Map<?, ?> rootMap) {
        List<Map<?, ?>> candidateMaps = new ArrayList<>();
        ArrayDeque<Object> queue = new ArrayDeque<>();
        queue.add(rootMap);

        while (!queue.isEmpty()) {
            Object current = queue.removeFirst();
            if (current instanceof Map<?, ?> map) {
                candidateMaps.add(map);
                for (Object value : map.values()) {
                    if (value instanceof Map<?, ?> || value instanceof List<?>) {
                        queue.addLast(value);
                    }
                }
            } else if (current instanceof List<?> list) {
                for (Object item : list) {
                    if (item instanceof Map<?, ?> || item instanceof List<?>) {
                        queue.addLast(item);
                    }
                }
            }
        }

        return candidateMaps;
    }

    private int countPresent(NutritionValues values) {
        int score = 0;
        if (values.calories() != null) score++;
        if (values.protein() != null) score++;
        if (values.fat() != null) score++;
        if (values.carbohydrates() != null) score++;
        return score;
    }

    private Double extractNumber(Map<?, ?> source, String[] keys) {
        for (String key : keys) {
            Object value = findValueIgnoreCase(source, key);
            Double parsed = parseNumber(value);
            if (parsed != null) {
                return parsed;
            }
        }
        return null;
    }

    private Object findValueIgnoreCase(Map<?, ?> source, String key) {
        if (source.containsKey(key)) {
            return source.get(key);
        }

        for (Map.Entry<?, ?> entry : source.entrySet()) {
            if (entry.getKey() instanceof String strKey && strKey.equalsIgnoreCase(key)) {
                return entry.getValue();
            }
        }

        return null;
    }

    private Double parseNumber(Object value) {
        if (value instanceof Number number) {
            return number.doubleValue();
        }

        if (value instanceof String text) {
            Matcher matcher = NUMBER_PATTERN.matcher(text.replace(",", ""));
            if (matcher.find()) {
                return Double.parseDouble(matcher.group());
            }
        }

        return null;
    }

    private boolean matchesAnyKey(String source, String[] keys) {
        String normalizedSource = source.trim().toLowerCase();
        for (String key : keys) {
            if (normalizedSource.contains(key.toLowerCase())) {
                return true;
            }
        }
        return false;
    }

    public record NutritionValues(Double calories, Double protein, Double fat, Double carbohydrates) {
    }
}
