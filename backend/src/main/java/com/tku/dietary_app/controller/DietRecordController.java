package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.ApiResponse;
import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.dto.DietRecordResponse;
import com.tku.dietary_app.dto.UserCustomDishResponse;
import com.tku.dietary_app.entity.MealType;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.exception.UnauthorizedException;
import com.tku.dietary_app.repository.UserRepository;
import com.tku.dietary_app.service.DietRecordService;
import jakarta.validation.Valid;
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
import java.time.format.DateTimeParseException;
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

    @GetMapping("/custom-dishes")
    public ResponseEntity<ApiResponse<?>> getCustomDishes() {
        User user = getLoginUser();
        return ResponseEntity.ok(ApiResponse.success(
                dietRecordService.getCustomDishesByUser(user.getId())
                        .stream()
                        .map(UserCustomDishResponse::fromEntity)
                        .toList()
        ));
    }

    @PostMapping
    public ResponseEntity<ApiResponse<?>> create(@RequestBody Object requestBody) {
        User user = getLoginUser();
        List<DietRecordRequest> requests = parseCreateRequests(requestBody);
        if (requests.isEmpty()) {
            throw new IllegalArgumentException("請至少提供一筆飲食紀錄");
        }

        List<DietRecordResponse> createdRecords = new ArrayList<>();
        for (DietRecordRequest request : requests) {
            validateRequest(request);
            createdRecords.add(DietRecordResponse.fromEntity(dietRecordService.create(user.getId(), request)));
        }

        if (createdRecords.size() == 1) {
            return ResponseEntity.ok(ApiResponse.success("飲食紀錄建立成功", createdRecords.get(0)));
        }

        return ResponseEntity.ok(ApiResponse.success("飲食紀錄建立成功", createdRecords));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiResponse<?>> update(@PathVariable Long id, @Valid @RequestBody DietRecordRequest request) {
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

    private void validateRequest(DietRecordRequest request) {
        if (request.getDishName() == null || request.getDishName().isBlank()) {
            throw new IllegalArgumentException("dishName 為必填欄位");
        }
        if (request.getDishName().length() > 255) {
            throw new IllegalArgumentException("dishName 長度不可超過 255 個字元");
        }
        if (request.getMealType() == null || request.getMealType().isBlank()) {
            throw new IllegalArgumentException("mealType 為必填欄位");
        }
        if (MealType.from(request.getMealType()) == null) {
            throw new IllegalArgumentException("mealType 只支援 breakfast、lunch、dinner 或 早餐、午餐、晚餐");
        }
        if (request.getCalories() != null && request.getCalories() < 0) {
            throw new IllegalArgumentException("calories 必須大於或等於 0");
        }
        if (request.getProtein() != null && request.getProtein() < 0) {
            throw new IllegalArgumentException("protein 必須大於或等於 0");
        }
        if (request.getFat() != null && request.getFat() < 0) {
            throw new IllegalArgumentException("fat 必須大於或等於 0");
        }
        if (request.getCarbohydrates() != null && request.getCarbohydrates() < 0) {
            throw new IllegalArgumentException("carbohydrates 必須大於或等於 0");
        }
        if (request.getAmount() != null && request.getAmount() <= 0) {
            throw new IllegalArgumentException("amount 必須大於 0");
        }
        if (request.getDescription() != null && request.getDescription().length() > 1000) {
            throw new IllegalArgumentException("description 長度不可超過 1000 個字元");
        }
    }

    private List<DietRecordRequest> parseCreateRequests(Object requestBody) {
        if (requestBody == null) {
            throw new IllegalArgumentException("請提供飲食紀錄資料");
        }

        if (requestBody instanceof List<?> list) {
            List<DietRecordRequest> requests = new ArrayList<>();
            for (Object item : list) {
                if (!(item instanceof Map<?, ?> itemMap)) {
                    throw new IllegalArgumentException("陣列中的每筆飲食紀錄格式不正確");
                }
                requests.add(parseSingleRequest(itemMap, null));
            }
            return requests;
        }

        if (requestBody instanceof Map<?, ?> map) {
            Object dishInfoList = map.get("dish_info_list");
            if (dishInfoList instanceof List<?> list) {
                List<DietRecordRequest> requests = new ArrayList<>();
                for (Object item : list) {
                    if (!(item instanceof Map<?, ?> itemMap)) {
                        throw new IllegalArgumentException("dish_info_list 中的每筆紀錄格式不正確");
                    }
                    requests.add(parseSingleRequest(itemMap, null));
                }
                return requests;
            }
            return List.of(parseSingleRequest(map, null));
        }

        throw new IllegalArgumentException("請提供正確的飲食紀錄資料格式");
    }

    private DietRecordRequest parseSingleRequest(Map<?, ?> item, String overrideDishName) {
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
        
        LocalDate parsedDate = readDate(item, "record_date", "date", "meal_date", "mealDate");
        request.setDate(parsedDate);
        request.setMealDate(parsedDate);
        
        request.setDescription(readText(item, "description"));
        request.setMealType(readText(item, "meal_type", "mealType"));
        request.setAmount(readInteger(item, "amount"));
        request.setType(readText(item, "type"));
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

    private LocalDate readDate(Map<?, ?> map, String... fieldNames) {
        String text = readText(map, fieldNames);
        if (text == null) {
            return null;
        }
        try {
            return LocalDate.parse(text);
        } catch (DateTimeParseException e) {
            throw new IllegalArgumentException("日期格式不正確 (" + text + ")，請使用 YYYY-MM-DD 格式");
        }
    }

    private Double readDouble(Map<?, ?> map, String fieldName) {
        Object value = map.get(fieldName);
        if (value == null || value.toString().isBlank()) {
            return null;
        }
        try {
            return Double.parseDouble(value.toString());
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException(fieldName + " 必須為有效數字");
        }
    }

    private Integer readInteger(Map<?, ?> map, String fieldName) {
        Object value = map.get(fieldName);
        if (value == null || value.toString().isBlank()) {
            return null;
        }
        try {
            return Integer.parseInt(value.toString());
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException(fieldName + " 必須為有效整數");
        }
    }
}
