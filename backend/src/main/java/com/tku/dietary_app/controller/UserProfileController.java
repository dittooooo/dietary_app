package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.dto.OnboardingRequest;
import com.tku.dietary_app.entity.DietRecord;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.service.DietRecordService;
import com.tku.dietary_app.service.UserProfileService;
import com.tku.dietary_app.repository.UserRepository;
import org.springframework.beans.factory.annotation.Autowired;//讓 Spring 自動把需要的物件注入進來
import org.springframework.http.ResponseEntity;//用來自訂 HTTP 回應內容，例如：狀態碼 200 / 401 / 404 / 500
import org.springframework.security.core.Authentication;//這是 Spring Security 裡代表「目前登入資訊」的物件
import org.springframework.security.core.context.SecurityContextHolder;//從 Spring Security 取得「目前登入者」的資訊
import org.springframework.validation.annotation.Validated;//這個註解用來啟用驗證功能。通常放在類別上，讓方法參數的驗證能生效
import org.springframework.web.bind.annotation.*;//匯入 Spring Web 的註解
import jakarta.validation.Valid;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/user")
@Validated
public class UserProfileController {
    @Autowired
    private UserProfileService userProfileService;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private DietRecordService dietRecordService;

    private User getAuthenticatedUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()) return null;
        return userRepository.findByEmail(authentication.getPrincipal().toString()).orElse(null);
    }

    // 取得自己的飲食紀錄
    @GetMapping("/diet-records")
    public ResponseEntity<?> getMyDietRecords() {
        User user = getAuthenticatedUser();
        if (user == null) return ResponseEntity.status(401).body(createErrorResponse("使用者未認證"));
        return ResponseEntity.ok(dietRecordService.getRecordsByUser(user.getId()));
    }

    // 新增自己的飲食紀錄
    @PostMapping("/diet-records")
    public ResponseEntity<?> addMyDietRecord(@RequestBody DietRecordRequest request) {
        User user = getAuthenticatedUser();
        if (user == null) return ResponseEntity.status(401).body(createErrorResponse("使用者未認證"));
        return ResponseEntity.ok(dietRecordService.create(user.getId(), request));
    }

    // 完成用戶 onboarding 流程
    @PostMapping("/onboarding")
    //ResponseEntity<?>：回傳 HTTP 回應
    public ResponseEntity<?> completeOnboarding(@Valid @RequestBody OnboardingRequest request) {
        try {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

            //沒有登入資訊，不是已登入狀態
            if (authentication == null || !authentication.isAuthenticated()) {
                return ResponseEntity.status(401).body(createErrorResponse("使用者未認證"));
            }

            // 從 principal 取得 email (String 型別)
            String email = authentication.getPrincipal().toString();

            // 根據 email 查詢 User
            Optional<User> userOptional = userRepository.findByEmail(email);
            if (userOptional.isEmpty()) {
                return ResponseEntity.status(401).body(createErrorResponse("無法取得使用者資訊"));
            }

            User user = userOptional.get();

            // 建立或更新 UserProfile
            UserProfile userProfile = userProfileService.createOrUpdateUserProfile(user, request);
            // 標記 onboarding 已完成
            user.setHasCompletedOnboarding(true);
            userRepository.save(user);//把更新後的 User 存回資料庫

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Onboarding 完成");
            response.put("data", userProfile);

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(createErrorResponse("發生錯誤: " + e.getMessage()));
        }
    }

    // 獲取用戶個人資料
    @GetMapping("/profile")
    public ResponseEntity<?> getUserProfile() {
        try {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

            if (authentication == null || !authentication.isAuthenticated()) {
                return ResponseEntity.status(401).body(createErrorResponse("使用者未認證"));
            }

            String email = authentication.getPrincipal().toString();

            Optional<User> userOptional = userRepository.findByEmail(email);
            if (userOptional.isEmpty()) {
                return ResponseEntity.status(401).body(createErrorResponse("無法取得使用者資訊"));
            }

            User user = userOptional.get();

            var userProfile = userProfileService.getUserProfile(user);

            if (userProfile.isEmpty()) {
                return ResponseEntity.status(404).body(createErrorResponse("使用者尚未完成 onboarding"));
            }

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("data", userProfile.get());

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(createErrorResponse("發生錯誤: " + e.getMessage()));
        }
    }

    // 創建錯誤響應的私有方法
    private Map<String, Object> createErrorResponse(String message) {
        Map<String, Object> error = new HashMap<>();
        error.put("success", false);
        error.put("message", message);
        return error;
    }
}
