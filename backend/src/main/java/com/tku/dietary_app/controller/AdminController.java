package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.AdminUserRequest;
import com.tku.dietary_app.dto.ApiResponse;
import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.dto.DietRecordResponse;
import com.tku.dietary_app.service.AdminService;
import com.tku.dietary_app.service.DietRecordService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
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

@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminController {

    private final AdminService adminService;
    private final DietRecordService dietRecordService;

    @GetMapping("/users")
    public ResponseEntity<ApiResponse<?>> listUsers(@RequestParam(required = false) String keyword) {
        if (keyword != null) {
            return ResponseEntity.ok(ApiResponse.success(adminService.searchUsers(keyword)));
        }
        return ResponseEntity.ok(ApiResponse.success(adminService.getAllUsers()));
    }

    @GetMapping("/users/{id}")
    public ResponseEntity<ApiResponse<?>> getUser(@PathVariable Long id) {
        return ResponseEntity.ok(ApiResponse.success(adminService.getUserById(id)));
    }

    @PostMapping("/users")
    public ResponseEntity<ApiResponse<?>> addUser(@Valid @RequestBody AdminUserRequest request) {
        return ResponseEntity.ok(ApiResponse.success("使用者建立成功", adminService.createUser(request)));
    }

    @PutMapping("/users/{id}")
    public ResponseEntity<ApiResponse<?>> editUser(@PathVariable Long id, @Valid @RequestBody AdminUserRequest request) {
        return ResponseEntity.ok(ApiResponse.success("使用者更新成功", adminService.updateUser(id, request)));
    }

    @DeleteMapping("/users/{id}")
    public ResponseEntity<ApiResponse<Void>> removeUser(@PathVariable Long id) {
        adminService.deleteUser(id);
        return ResponseEntity.ok(ApiResponse.success("使用者刪除成功", null));
    }

    @GetMapping("/diet-records")
    public ResponseEntity<ApiResponse<?>> listDietRecords(@RequestParam(required = false) Long userId,
                                                          @RequestParam(required = false) String nickname,
                                                          @RequestParam(required = false) String dishName,
                                                          @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
                                                          @RequestParam(required = false) String mealType,
                                                          @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate weekStart) {
        return ResponseEntity.ok(ApiResponse.success(
                dietRecordService.getAdminRecords(userId, nickname, dishName, date, mealType, weekStart)
                        .stream()
                        .map(DietRecordResponse::fromEntity)
                        .toList()
        ));
    }

    @PostMapping("/diet-records")
    public ResponseEntity<ApiResponse<?>> addDietRecord(@RequestParam Long userId, @Valid @RequestBody DietRecordRequest request) {
        return ResponseEntity.ok(ApiResponse.success(
                "飲食紀錄建立成功",
                DietRecordResponse.fromEntity(dietRecordService.create(userId, request))
        ));
    }

    @PutMapping("/diet-records/{id}")
    public ResponseEntity<ApiResponse<?>> editDietRecord(@PathVariable Long id, @Valid @RequestBody DietRecordRequest request) {
        return ResponseEntity.ok(ApiResponse.success(
                "飲食紀錄更新成功",
                DietRecordResponse.fromEntity(dietRecordService.updateByAdmin(id, request))
        ));
    }

    @DeleteMapping("/diet-records/{id}")
    public ResponseEntity<ApiResponse<Void>> removeDietRecord(@PathVariable Long id) {
        dietRecordService.deleteByAdmin(id);
        return ResponseEntity.ok(ApiResponse.success("飲食紀錄刪除成功", null));
    }

    @PostMapping("/diet-records/{id}/photo")
    public ResponseEntity<ApiResponse<?>> uploadDietPhoto(@PathVariable Long id,
                                                          @RequestParam("file") MultipartFile file) throws IOException {
        return ResponseEntity.ok(ApiResponse.success(
                "照片上傳成功",
                dietRecordService.savePhotoByAdmin(id, file)
        ));
    }
}
