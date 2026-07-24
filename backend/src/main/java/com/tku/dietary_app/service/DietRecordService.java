package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.entity.DietRecord;
import com.tku.dietary_app.entity.MealType;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.DietRecordRepository;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class DietRecordService {

    private final DietRecordRepository dietRecordRepository;
    private final UserRepository userRepository;
    private final DietaryAgentService dietaryAgentService;

    @Value("${app.upload.dir}")
    private String uploadDir;

    public List<DietRecord> getAllRecords() {
        return dietRecordRepository.findAll();
    }

    public List<DietRecord> searchByDishName(String dishName) {
        return dietRecordRepository.findByDishNameContainingIgnoreCase(dishName);
    }

    public List<DietRecord> getRecordsByUser(Long userId) {
        return dietRecordRepository.findByUserIdOrderByCreatedAtDescIdDesc(userId);
    }

    public List<DietRecord> getAdminRecords(Long userId, String nickname, String dishName, LocalDate date, String mealType, LocalDate weekStart) {
        if (date != null && weekStart != null) {
            throw new IllegalArgumentException("date 與 weekStart 不能同時使用");
        }

        LocalDateTime startAt = null;
        LocalDateTime endAt = null;

        if (date != null) {
            startAt = date.atStartOfDay();
            endAt = date.plusDays(1).atStartOfDay();
        } else if (weekStart != null) {
            startAt = weekStart.atStartOfDay();
            endAt = weekStart.plusDays(7).atStartOfDay();
        }

        MealType normalizedMealType = MealType.from(mealType);
        return dietRecordRepository.findByAdminFilters(
                userId,
                normalizeKeyword(nickname),
                normalizeKeyword(dishName),
                normalizedMealType == null ? null : normalizedMealType.name(),
                startAt,
                endAt
        );
    }

    public DietRecord create(Long userId, DietRecordRequest request) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("找不到使用者 (ID: " + userId + ")"));

        DietaryAgentService.NutritionValues nutritionValues = dietaryAgentService.fetchDishNutrition(request.getDishName());

        return dietRecordRepository.save(DietRecord.builder()
                .user(user)
                .dishName(request.getDishName())
                .calories(selectNutritionValue(nutritionValues.calories(), request.getCalories()))
                .protein(selectNutritionValue(nutritionValues.protein(), request.getProtein()))
                .fat(selectNutritionValue(nutritionValues.fat(), request.getFat()))
                .carbohydrates(selectNutritionValue(nutritionValues.carbohydrates(), request.getCarbohydrates()))
                .description(request.getDescription())
                .mealType(normalizeMealType(request.getMealType()))
                .build());
    }

    public DietRecord updateByAdmin(Long id, DietRecordRequest request) {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到飲食紀錄 (ID: " + id + ")"));
        record.setDishName(request.getDishName());
        record.setCalories(request.getCalories());
        record.setProtein(request.getProtein());
        record.setFat(request.getFat());
        record.setCarbohydrates(request.getCarbohydrates());
        record.setDescription(request.getDescription());
        record.setMealType(normalizeMealType(request.getMealType()));
        return dietRecordRepository.save(record);
    }

    public void deleteByAdmin(Long id) {
        if (!dietRecordRepository.existsById(id)) {
            throw new RuntimeException("找不到飲食紀錄 (ID: " + id + ")");
        }
        dietRecordRepository.deleteById(id);
    }

    public DietRecord update(Long id, Long loginUserId, DietRecordRequest request) {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到飲食紀錄 (ID: " + id + ")"));
        if (!record.getUser().getId().equals(loginUserId)) {
            throw new RuntimeException("無權編輯此紀錄");
        }
        record.setDishName(request.getDishName());
        record.setCalories(request.getCalories());
        record.setProtein(request.getProtein());
        record.setFat(request.getFat());
        record.setCarbohydrates(request.getCarbohydrates());
        record.setDescription(request.getDescription());
        record.setMealType(normalizeMealType(request.getMealType()));
        return dietRecordRepository.save(record);
    }

    public DietRecord savePhotoByAdmin(Long id, MultipartFile file) throws IOException {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到飲食紀錄 (ID: " + id + ")"));

        String ext = file.getOriginalFilename() != null && file.getOriginalFilename().contains(".")
                ? file.getOriginalFilename().substring(file.getOriginalFilename().lastIndexOf("."))
                : ".jpg";
        String filename = "diet_" + id + "_" + UUID.randomUUID() + ext;

        Path dir = Paths.get(uploadDir.replace("avatars", "diet"));
        Files.createDirectories(dir);
        Files.copy(file.getInputStream(), dir.resolve(filename),
                java.nio.file.StandardCopyOption.REPLACE_EXISTING);

        record.setPhotoUrl("/diet/" + filename);
        return dietRecordRepository.save(record);
    }

    public DietRecord savePhoto(Long id, Long loginUserId, MultipartFile file) throws IOException {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到飲食紀錄 (ID: " + id + ")"));
        if (!record.getUser().getId().equals(loginUserId)) {
            throw new RuntimeException("無權上傳此紀錄的照片");
        }

        String ext = file.getOriginalFilename() != null && file.getOriginalFilename().contains(".")
                ? file.getOriginalFilename().substring(file.getOriginalFilename().lastIndexOf("."))
                : ".jpg";
        String filename = "diet_" + id + "_" + UUID.randomUUID() + ext;

        Path dir = Paths.get(uploadDir.replace("avatars", "diet"));
        Files.createDirectories(dir);
        Files.copy(file.getInputStream(), dir.resolve(filename),
                java.nio.file.StandardCopyOption.REPLACE_EXISTING);

        record.setPhotoUrl("/diet/" + filename);
        return dietRecordRepository.save(record);
    }

    public void delete(Long id, Long loginUserId) {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到飲食紀錄 (ID: " + id + ")"));
        if (!record.getUser().getId().equals(loginUserId)) {
            throw new RuntimeException("無權刪除此紀錄");
        }
        dietRecordRepository.deleteById(id);
    }

    private String normalizeMealType(String mealType) {
        MealType normalizedMealType = MealType.from(mealType);
        return normalizedMealType == null ? null : normalizedMealType.name();
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
}
