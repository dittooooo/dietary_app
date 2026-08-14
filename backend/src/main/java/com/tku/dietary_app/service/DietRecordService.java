package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.entity.DietRecord;
import com.tku.dietary_app.entity.MealType;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.exception.ForbiddenOperationException;
import com.tku.dietary_app.exception.ResourceNotFoundException;
import com.tku.dietary_app.repository.DietRecordRepository;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.Objects;

@Service
@RequiredArgsConstructor
public class DietRecordService {

    private final DietRecordRepository dietRecordRepository;
    private final UserRepository userRepository;
    private final DietaryAgentService dietaryAgentService;
    private final Clock taipeiClock;
    private final ImageStorageService imageStorageService;

    @Value("${app.upload.dir}")
    private String uploadDir;

    public List<DietRecord> getAllRecords() {
        return dietRecordRepository.findAll();
    }

    public List<DietRecord> searchByDishName(String dishName) {
        return dietRecordRepository.findByDishNameContainingIgnoreCase(dishName);
    }

    public List<DietRecord> getRecordsByUser(Long userId) {
        return dietRecordRepository.findByUserIdOrderByDateDescCreatedAtDescIdDesc(userId);
    }

    public List<DietRecord> getAdminRecords(Long userId, String nickname, String dishName, LocalDate date, String mealType, LocalDate weekStart) {
        if (date != null && weekStart != null) {
            throw new IllegalArgumentException("date 與 weekStart 不能同時提供");
        }

        LocalDate startDate = null;
        LocalDate endDate = null;

        if (date != null) {
            startDate = date;
            endDate = date.plusDays(1);
        } else if (weekStart != null) {
            startDate = weekStart;
            endDate = weekStart.plusDays(7);
        }

        MealType normalizedMealType = MealType.from(mealType);
        return dietRecordRepository.findByAdminFilters(
                userId,
                normalizeKeyword(nickname),
                normalizeKeyword(dishName),
                normalizedMealType == null ? null : normalizedMealType.name(),
                startDate,
                endDate
        );
    }

    public DietRecord create(Long userId, DietRecordRequest request) {
        validateCreateRequest(request);

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResourceNotFoundException("找不到使用者 (ID: " + userId + ")"));

        DietaryAgentService.NutritionValues nutritionValues = dietaryAgentService.fetchDishNutrition(request.getDishName().trim());

        LocalDate recordDate = resolveRecordDateForCreate(request);

        return dietRecordRepository.save(DietRecord.builder()
                .user(user)
                .dishName(request.getDishName().trim())
                .calories(selectNutritionValue(nutritionValues.calories(), request.getCalories()))
                .protein(selectNutritionValue(nutritionValues.protein(), request.getProtein()))
                .fat(selectNutritionValue(nutritionValues.fat(), request.getFat()))
                .carbohydrates(selectNutritionValue(nutritionValues.carbohydrates(), request.getCarbohydrates()))
                .date(recordDate)
                .mealDate(recordDate)
                .description(normalizeNullableText(request.getDescription()))
                .mealType(normalizeMealTypeRequired(request.getMealType()))
                .amount(resolveAmount(request.getAmount()))
                .build());
    }

    public DietRecord updateByAdmin(Long id, DietRecordRequest request) {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("找不到飲食紀錄 (ID: " + id + ")"));
        applyUpdates(record, request);
        return dietRecordRepository.save(record);
    }

    public void deleteByAdmin(Long id) {
        if (!dietRecordRepository.existsById(id)) {
            throw new ResourceNotFoundException("找不到飲食紀錄 (ID: " + id + ")");
        }
        dietRecordRepository.deleteById(id);
    }

    public DietRecord update(Long id, Long loginUserId, DietRecordRequest request) {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("找不到飲食紀錄 (ID: " + id + ")"));
        if (!record.getUser().getId().equals(loginUserId)) {
            throw new ForbiddenOperationException("無權編輯此紀錄");
        }
        applyUpdates(record, request);
        return dietRecordRepository.save(record);
    }

    public DietRecord savePhotoByAdmin(Long id, MultipartFile file) throws IOException {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("找不到飲食紀錄 (ID: " + id + ")"));

        Path dir = Paths.get(uploadDir.replace("avatars", "diet"));
        String filename = imageStorageService.storeImage(file, dir, "diet_" + id);

        record.setPhotoUrl("/diet/" + filename);
        return dietRecordRepository.save(record);
    }

    public DietRecord savePhoto(Long id, Long loginUserId, MultipartFile file) throws IOException {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("找不到飲食紀錄 (ID: " + id + ")"));
        if (!record.getUser().getId().equals(loginUserId)) {
            throw new ForbiddenOperationException("無權上傳此紀錄的照片");
        }

        Path dir = Paths.get(uploadDir.replace("avatars", "diet"));
        String filename = imageStorageService.storeImage(file, dir, "diet_" + id);

        record.setPhotoUrl("/diet/" + filename);
        return dietRecordRepository.save(record);
    }

    public void delete(Long id, Long loginUserId) {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("找不到飲食紀錄 (ID: " + id + ")"));
        if (!record.getUser().getId().equals(loginUserId)) {
            throw new ForbiddenOperationException("無權刪除此紀錄");
        }
        dietRecordRepository.deleteById(id);
    }

    private void applyUpdates(DietRecord record, DietRecordRequest request) {
        String nextDishName = hasText(request.getDishName()) ? request.getDishName().trim() : record.getDishName();
        boolean dishNameChanged = !Objects.equals(record.getDishName(), nextDishName);
        DietaryAgentService.NutritionValues nutritionValues = dishNameChanged
                ? dietaryAgentService.fetchDishNutrition(nextDishName)
                : null;

        record.setDishName(nextDishName);
        record.setCalories(resolveUpdatedNutritionValue(request.getCalories(), dishNameChanged, nutritionValues == null ? null : nutritionValues.calories(), record.getCalories()));
        record.setProtein(resolveUpdatedNutritionValue(request.getProtein(), dishNameChanged, nutritionValues == null ? null : nutritionValues.protein(), record.getProtein()));
        record.setFat(resolveUpdatedNutritionValue(request.getFat(), dishNameChanged, nutritionValues == null ? null : nutritionValues.fat(), record.getFat()));
        record.setCarbohydrates(resolveUpdatedNutritionValue(request.getCarbohydrates(), dishNameChanged, nutritionValues == null ? null : nutritionValues.carbohydrates(), record.getCarbohydrates()));

        LocalDate requestedDate = resolveRequestedDate(request);
        if (requestedDate != null) {
            record.setDate(requestedDate);
            record.setMealDate(requestedDate);
        }
        if (request.getDescription() != null) {
            record.setDescription(normalizeNullableText(request.getDescription()));
        }
        if (hasText(request.getMealType())) {
            record.setMealType(normalizeMealTypeRequired(request.getMealType()));
        }
        record.setAmount(resolveAmount(request.getAmount()));
    }

    private Double resolveUpdatedNutritionValue(Double requestValue,
                                                boolean dishNameChanged,
                                                Double refreshedValue,
                                                Double currentValue) {
        if (requestValue != null) {
            return requestValue;
        }
        if (dishNameChanged && refreshedValue != null) {
            return refreshedValue;
        }
        return currentValue;
    }

    private String normalizeMealTypeRequired(String mealType) {
        MealType normalizedMealType = MealType.from(mealType);
        if (normalizedMealType == null) {
            throw new IllegalArgumentException("mealType 為必填欄位");
        }
        return normalizedMealType.name();
    }

    private String normalizeKeyword(String keyword) {
        if (keyword == null || keyword.isBlank()) {
            return null;
        }
        return keyword.trim();
    }

    private Double selectNutritionValue(Double resolvedValue, Double fallbackValue) {
        return resolvedValue != null ? resolvedValue : fallbackValue;
    }

    private LocalDate resolveRecordDateForCreate(DietRecordRequest request) {
        LocalDate requestedDate = resolveRequestedDate(request);
        return requestedDate != null ? requestedDate : LocalDate.now(taipeiClock);
    }

    private LocalDate resolveRequestedDate(DietRecordRequest request) {
        return request.getDate() != null ? request.getDate() : request.getMealDate();
    }

    private int resolveAmount(Integer amount) {
        return amount == null ? 1 : amount;
    }

    private void validateCreateRequest(DietRecordRequest request) {
        if (!hasText(request.getDishName())) {
            throw new IllegalArgumentException("dishName 為必填欄位");
        }
        if (!hasText(request.getMealType())) {
            throw new IllegalArgumentException("mealType 為必填欄位");
        }
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }

    private String normalizeNullableText(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
