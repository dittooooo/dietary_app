package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.ApiResponse;
import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.dto.DietRecordResponse;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.exception.UnauthorizedException;
import com.tku.dietary_app.repository.UserRepository;
import com.tku.dietary_app.service.DietRecordService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/diet-records")
@RequiredArgsConstructor
public class DietRecordController {

    private final DietRecordService dietRecordService;
    private final UserRepository userRepository;

    private User getLoginUser() {
        String email = SecurityContextHolder.getContext().getAuthentication().getPrincipal().toString();
        return userRepository.findByEmail(email)
                .orElseThrow(() -> new UnauthorizedException("登入狀態無效"));
    }

    @GetMapping
    public ResponseEntity<ApiResponse<?>> getRecords() {
        User user = getLoginUser();
        return ResponseEntity.ok(ApiResponse.success(
                dietRecordService.getRecordsByUser(user.getId())
                        .stream()
                        .map(DietRecordResponse::fromEntity)
                        .toList()
        ));
    }

    @PostMapping
    public ResponseEntity<ApiResponse<?>> create(@RequestBody Object requestBody) {
        User user = getLoginUser();
        List<DietRecordRequest> requests = parseCreateRequests(requestBody);
        if (requests.isEmpty()) {
            throw new IllegalArgumentException("dish_info_list 至少需要一筆");
        }

        List<DietRecordResponse> createdRecords = new ArrayList<>();
        for (DietRecordRequest request : requests) {
            createdRecords.add(DietRecordResponse.fromEntity(dietRecordService.create(user.getId(), request)));
        }

        if (createdRecords.size() == 1) {
            return ResponseEntity.ok(ApiResponse.success("飲食紀錄建立成功", createdRecords.get(0)));
        }

        return ResponseEntity.ok(ApiResponse.success("飲食紀錄建立成功", createdRecords));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiResponse<?>> update(@PathVariable Long id, @RequestBody DietRecordRequest request) {
        User user = getLoginUser();
        return ResponseEntity.ok(ApiResponse.success(
                "飲食紀錄更新成功",
                DietRecordResponse.fromEntity(dietRecordService.update(id, user.getId(), request))
        ));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse<Void>> delete(@PathVariable Long id) {
        User user = getLoginUser();
        dietRecordService.delete(id, user.getId());
        return ResponseEntity.ok(ApiResponse.success("飲食紀錄刪除成功", null));
    }

    @PostMapping("/{id}/photo")
    public ResponseEntity<ApiResponse<?>> uploadPhoto(@PathVariable Long id, @RequestParam("file") MultipartFile file) throws IOException {
        User user = getLoginUser();
        return ResponseEntity.ok(ApiResponse.success(
                "照片上傳成功",
                dietRecordService.savePhoto(id, user.getId(), file)
        ));
    }

    private List<DietRecordRequest> parseCreateRequests(Object requestBody) {
        if (requestBody == null) {
            throw new IllegalArgumentException("請提供飲食紀錄資料");
        }

        if (requestBody instanceof List<?> list) {
            List<DietRecordRequest> requests = new ArrayList<>();
            for (Object item : list) {
                requests.addAll(parseSingleRequestWithSplit((Map<?, ?>) item));
            }
            return requests;
        }

        if (requestBody instanceof Map<?, ?> map) {
            Object dishInfoList = map.get("dish_info_list");
            if (dishInfoList instanceof List<?> list) {
                List<DietRecordRequest> requests = new ArrayList<>();
                for (Object item : list) {
                    requests.addAll(parseSingleRequestWithSplit((Map<?, ?>) item));
                }
                return requests;
            }
            return parseSingleRequestWithSplit(map);
        }

        throw new IllegalArgumentException("請提供正確的飲食紀錄資料格式");
    }

    private List<DietRecordRequest> parseSingleRequestWithSplit(Map<?, ?> item) {
        if (item == null) {
            throw new IllegalArgumentException("飲食紀錄資料不可為空");
        }

        String rawDishName = readText(item, "dish_name", "dishName");
        if (rawDishName == null || rawDishName.isBlank()) {
            return List.of(parseSingleRequest(item, null));
        }

        String[] dishNames = rawDishName.split("[,，]");
        List<DietRecordRequest> requests = new ArrayList<>();

        for (String name : dishNames) {
            String trimmedName = name.trim();
            if (!trimmedName.isEmpty()) {
                requests.add(parseSingleRequest(item, trimmedName));
            }
        }

        if (requests.isEmpty()) {
            return List.of(parseSingleRequest(item, null));
        }

        return requests;
    }

    private DietRecordRequest parseSingleRequest(Map<?, ?> item, String overrideDishName) {
        if (item == null) {
            throw new IllegalArgumentException("飲食紀錄資料不可為空");
        }

        DietRecordRequest request = new DietRecordRequest();
        if (overrideDishName != null) {
            request.setDishName(overrideDishName);
        } else {
            request.setDishName(readText(item, "dish_name", "dishName"));
        }
        request.setCalories(readDouble(item, "calories"));
        request.setProtein(readDouble(item, "protein"));
        request.setFat(readDouble(item, "fat"));
        request.setCarbohydrates(readDouble(item, "carbohydrates"));
        String recordDateText = readText(item, "record_date", "date");
        request.setDate(recordDateText == null ? null : LocalDate.parse(recordDateText));
        request.setDescription(readText(item, "description"));
        request.setMealType(readText(item, "meal_type", "mealType"));
        request.setAmount(readInteger(item, "amount"));
        return request;
    }

    private String readText(Map<?, ?> map, String... fieldNames) {
        for (String fieldName : fieldNames) {
            Object value = map.get(fieldName);
            if (value != null && !(value instanceof String str && str.isBlank()) && !value.toString().isBlank()) {
                return value.toString();
            }
        }
        return null;
    }

    private Double readDouble(Map<?, ?> map, String fieldName) {
        Object value = map.get(fieldName);
        if (value == null || value.toString().isBlank()) {
            return null;
        }
        return Double.parseDouble(value.toString());
    }

    private Integer readInteger(Map<?, ?> map, String fieldName) {
        Object value = map.get(fieldName);
        if (value == null || value.toString().isBlank()) {
            return null;
        }
        return Integer.parseInt(value.toString());
    }
}
