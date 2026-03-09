package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.OnboardingRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.service.UserProfileService;
import com.tku.dietary_app.repository.UserRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;
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

    // 完成用戶 onboarding 流程
    @PostMapping("/onboarding")
    public ResponseEntity<?> completeOnboarding(@Valid @RequestBody OnboardingRequest request) {
        try {
            // 從 SecurityContext 取得目前登入的使用者 email
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

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
