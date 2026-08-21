package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.DietaryAgentPayload;
import com.tku.dietary_app.dto.DietaryAgentPayload.DishInfoDto;
import com.tku.dietary_app.dto.DietaryAgentPayload.HealthConditionDto;
import com.tku.dietary_app.dto.DietaryAgentPayload.WeeklyDietRecordDto;
import com.tku.dietary_app.dto.DietaryAskRequest;
import com.tku.dietary_app.dto.DietaryDishNutritionRequest;
import com.tku.dietary_app.entity.DietRecord;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.exception.ResourceNotFoundException;
import com.tku.dietary_app.exception.UpstreamServiceException;
import com.tku.dietary_app.repository.DietRecordRepository;
import com.tku.dietary_app.repository.UserProfileRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class DietaryAgentService {
    private static final Pattern NUMBER_PATTERN = Pattern.compile("-?\\d+(\\.\\d+)?");

    private static final String[] CALORIES_KEYS = {"calories", "calorie", "kcal"};
    private static final String[] PROTEIN_KEYS = {"protein", "proteins"};
    private static final String[] FAT_KEYS = {"fat"};
    private static final String[] CARBOHYDRATES_KEYS = {"carbohydrates", "carbohydrate", "carbs", "carb"};

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
        UserProfile userProfile = userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new ResourceNotFoundException("找不到使用者個人資料"));

        DietaryAgentPayload payload = buildPayload(userId, request, userProfile);
        return callPartnerApi(partnerApiAskPath, payload);
    }

    public Object dishNutrition(DietaryDishNutritionRequest request) {
        return callPartnerApi(partnerApiDishNutritionPath, request);
    }

    public NutritionValues fetchDishNutrition(String dishName) {
        if (dishName == null || dishName.isBlank()) {
            throw new IllegalArgumentException("dishName 為必填欄位");
        }

        DietaryDishNutritionRequest request = new DietaryDishNutritionRequest();
        request.setDishName(dishName.trim());
        Object response = dishNutrition(request);

        return parseNutritionValues(response);
    }

    private DietaryAgentPayload buildPayload(Long userId, DietaryAskRequest request, UserProfile userProfile) {
        Integer resolvedAge = AgeCalculator.calculateAge(userProfile.getBirthDate(), userProfile.getAge());
        DietaryAgentPayload.UserProfileDto userProfileDto = request.getUserProfile() != null
                ? DietaryAgentPayload.UserProfileDto.builder()
                .heightCm(request.getUserProfile().getHeightCm())
                .weightKg(request.getUserProfile().getWeightKg())
                .gender(request.getUserProfile().getGender())
                .age(request.getUserProfile().getAge() != null ? request.getUserProfile().getAge() : resolvedAge)
                .dietGoal(request.getUserProfile().getDietGoal())
                .build()
                : DietaryAgentPayload.UserProfileDto.builder()
                .heightCm(userProfile.getHeight())
                .weightKg(userProfile.getWeight())
                .gender(userProfile.getGender())
                .age(resolvedAge)
                .dietGoal(userProfile.getDietGoal())
                .build();

        HealthConditionDto healthConditionDto = request.getHealthCondition() != null
                ? DietaryAgentPayload.HealthConditionDto.builder()
                .hasChronicDisease(request.getHealthCondition().getHasChronicDisease())
                .chronicDiseases(request.getHealthCondition().getChronicDiseases())
                .build()
                : buildHealthConditionDto(userProfile);

        List<WeeklyDietRecordDto> weeklyDietRecords = request.getWeeklyDietRecords() != null
                ? flattenWeeklyDietRecords(request.getWeeklyDietRecords())
                : fetchWeeklyDietRecords(userId);

        List<DishInfoDto> dishInfoList = request.getDishInfoList() == null
                ? List.of()
                : request.getDishInfoList().stream()
                .map(dish -> DishInfoDto.builder()
                        .dishName(dish.getDishName())
                        .amount(dish.getAmount())
                        .build())
                .collect(Collectors.toList());

        return DietaryAgentPayload.builder()
                .question(request.getQuestion())
                .questionType(request.getQuestionType())
                .dishInfoList(dishInfoList)
                .userProfile(userProfileDto)
                .healthCondition(healthConditionDto)
                .weeklyDietRecords(weeklyDietRecords)
                .build();
    }

    private List<WeeklyDietRecordDto> flattenWeeklyDietRecords(List<DietaryAskRequest.WeeklyDietRecordDto> records) {
        if (records == null || records.isEmpty()) {
            return List.of();
        }

        List<WeeklyDietRecordDto> flattened = new ArrayList<>();
        for (DietaryAskRequest.WeeklyDietRecordDto weeklyRecord : records) {
            if (weeklyRecord == null || weeklyRecord.getRecord() == null || weeklyRecord.getRecord().isEmpty()) {
                continue;
            }
            for (DietaryAskRequest.WeeklyMealRecordDto mealRecord : weeklyRecord.getRecord()) {
                flattened.add(WeeklyDietRecordDto.builder()
                        .date(weeklyRecord.getDate())
                        .meal(mealRecord.getMealType())
                        .dishName(mealRecord.getDishName())
                        .note(mealRecord.getNote())
                        .build());
            }
        }
        return flattened;
    }

    private HealthConditionDto buildHealthConditionDto(UserProfile userProfile) {
        List<String> chronicDiseases = parseHealthConditions(userProfile.getHealthConditions());
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
                .map(record -> WeeklyDietRecordDto.builder()
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

    private Object callPartnerApi(String apiPath, Object payload) {
        if (partnerApiBaseUrl == null || partnerApiBaseUrl.isBlank()) {
            throw new IllegalStateException("未設定 dietary partner API base URL");
        }
        if (apiPath == null || apiPath.isBlank()) {
            throw new IllegalStateException("未設定 dietary partner API path");
        }

        String url = partnerApiBaseUrl.endsWith("/")
                ? partnerApiBaseUrl.substring(0, partnerApiBaseUrl.length() - 1) + apiPath
                : partnerApiBaseUrl + apiPath;

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        HttpEntity<Object> requestEntity = new HttpEntity<>(payload, headers);
        try {
            return restTemplate.postForObject(url, requestEntity, Object.class);
        } catch (ResourceAccessException ex) {
            throw new UpstreamServiceException("dietary partner API 連線逾時或無法連線");
        } catch (RestClientException ex) {
            throw new UpstreamServiceException("dietary partner API 呼叫失敗");
        }
    }

    private NutritionValues parseNutritionValues(Object response) {
        if (!(response instanceof Map<?, ?> rootMap)) {
            throw new UpstreamServiceException("dish-nutrition 回應格式不正確");
        }

        NutritionValues nutrientsArrayMatch = extractFromNutrientsArray(rootMap);
        int nutrientsArrayScore = countPresent(nutrientsArrayMatch);

        List<Map<?, ?>> candidateMaps = collectCandidateMaps(rootMap);

        NutritionValues bestMatch = null;
        int bestScore = nutrientsArrayScore;

        if (nutrientsArrayScore > 0) {
            bestMatch = nutrientsArrayMatch;
        }

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

        if (bestMatch == null) {
            return new NutritionValues(null, null, null, null);
        }

        return bestMatch;
    }

    private NutritionValues extractFromNutrientsArray(Map<?, ?> rootMap) {
        List<?> nutrientsList = findNutrientsList(rootMap);
        if (nutrientsList == null || nutrientsList.isEmpty()) {
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

            if (matchesAnyKey(nutrientName, CALORIES_KEYS, "熱量", "熱量(kcal)", "能量", "energy")) {
                calories = amount;
            } else if (matchesAnyKey(nutrientName, PROTEIN_KEYS, "蛋白質", "protein")) {
                protein = amount;
            } else if (matchesAnyKey(nutrientName, FAT_KEYS, "脂肪", "fat")) {
                fat = amount;
            } else if (matchesAnyKey(nutrientName, CARBOHYDRATES_KEYS, "碳水化合物", "碳水", "carbohydrate")) {
                carbohydrates = amount;
            }
        }

        return new NutritionValues(calories, protein, fat, carbohydrates);
    }

    private List<?> findNutrientsList(Object value) {
        if (value instanceof Map<?, ?> map) {
            Object nutrients = findValueIgnoreCase(map, "nutrients");
            if (nutrients instanceof List<?> nutrientsList) {
                return nutrientsList;
            }

            for (Object child : map.values()) {
                List<?> nested = findNutrientsList(child);
                if (nested != null && !nested.isEmpty()) {
                    return nested;
                }
            }
        } else if (value instanceof List<?> list) {
            for (Object child : list) {
                List<?> nested = findNutrientsList(child);
                if (nested != null && !nested.isEmpty()) {
                    return nested;
                }
            }
        }

        return null;
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
        return matchesAnyKey(source, keys, new String[0]);
    }

    private boolean matchesAnyKey(String source, String[] keys, String... extraKeys) {
        String normalizedSource = source.trim().toLowerCase();
        for (String key : keys) {
            if (normalizedSource.contains(key.toLowerCase())) {
                return true;
            }
        }
        for (String key : extraKeys) {
            if (normalizedSource.contains(key.toLowerCase())) {
                return true;
            }
        }
        return false;
    }

    public record NutritionValues(Double calories, Double protein, Double fat, Double carbohydrates) {
    }
}
