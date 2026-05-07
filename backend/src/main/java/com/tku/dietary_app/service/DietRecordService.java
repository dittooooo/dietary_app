package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.entity.DietRecord;
import com.tku.dietary_app.entity.MealType;
import com.tku.dietary_app.repository.DietRecordRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class DietRecordService {

    private final DietRecordRepository dietRecordRepository;

    public List<DietRecord> getAllRecords() {
        return dietRecordRepository.findAll();
    }

    public List<DietRecord> searchByDishName(String dishName) {
        return dietRecordRepository.findByDishNameContainingIgnoreCase(dishName);
    }

    public List<DietRecord> getAdminRecords(String dishName, LocalDate date, String mealType, LocalDate weekStart) {
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
                normalizeKeyword(dishName),
                normalizedMealType == null ? null : normalizedMealType.name(),
                startAt,
                endAt
        );
    }

    public DietRecord create(DietRecordRequest request) {
        return dietRecordRepository.save(DietRecord.builder()
                .dishName(request.getDishName())
                .nutrition(request.getNutrition())
                .cumulativeNutrition(request.getCumulativeNutrition())
                .healthLevel(request.getHealthLevel())
                .mealType(normalizeMealType(request.getMealType()))
                .build());
    }

    public DietRecord update(Long id, DietRecordRequest request) {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到飲食紀錄 (ID: " + id + ")"));
        record.setDishName(request.getDishName());
        record.setNutrition(request.getNutrition());
        record.setCumulativeNutrition(request.getCumulativeNutrition());
        record.setHealthLevel(request.getHealthLevel());
        record.setMealType(normalizeMealType(request.getMealType()));
        return dietRecordRepository.save(record);
    }

    public void delete(Long id) {
        if (!dietRecordRepository.existsById(id)) {
            throw new RuntimeException("找不到飲食紀錄 (ID: " + id + ")");
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
}
