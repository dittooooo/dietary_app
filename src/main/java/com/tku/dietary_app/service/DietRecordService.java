package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.entity.DietRecord;
import com.tku.dietary_app.repository.DietRecordRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

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

    public DietRecord create(DietRecordRequest request) {
        return dietRecordRepository.save(DietRecord.builder()
                .dishName(request.getDishName())
                .nutrition(request.getNutrition())
                .cumulativeNutrition(request.getCumulativeNutrition())
                .healthLevel(request.getHealthLevel())
                .build());
    }

    public DietRecord update(Long id, DietRecordRequest request) {
        DietRecord record = dietRecordRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到飲食紀錄 (ID: " + id + ")"));
        record.setDishName(request.getDishName());
        record.setNutrition(request.getNutrition());
        record.setCumulativeNutrition(request.getCumulativeNutrition());
        record.setHealthLevel(request.getHealthLevel());
        return dietRecordRepository.save(record);
    }

    public void delete(Long id) {
        if (!dietRecordRepository.existsById(id)) {
            throw new RuntimeException("找不到飲食紀錄 (ID: " + id + ")");
        }
        dietRecordRepository.deleteById(id);
    }
}
