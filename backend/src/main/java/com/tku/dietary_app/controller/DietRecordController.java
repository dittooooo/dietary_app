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
    public ResponseEntity<ApiResponse<?>> create(@RequestBody DietRecordRequest request) {
        User user = getLoginUser();
        return ResponseEntity.ok(ApiResponse.success(
                "飲食紀錄建立成功",
                DietRecordResponse.fromEntity(dietRecordService.create(user.getId(), request))
        ));
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
}
