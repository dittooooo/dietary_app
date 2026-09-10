package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.ApiResponse;
import com.tku.dietary_app.dto.OnboardingRequest;
import com.tku.dietary_app.dto.ProblemFeedbackRequest;
import com.tku.dietary_app.dto.ProblemFeedbackResponse;
import com.tku.dietary_app.dto.UserProfileResponse;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.exception.ResourceNotFoundException;
import com.tku.dietary_app.exception.UnauthorizedException;
import com.tku.dietary_app.repository.UserRepository;
import com.tku.dietary_app.service.AuthService;
import com.tku.dietary_app.service.ProblemFeedbackService;
import com.tku.dietary_app.service.UserProfileService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;

@RestController
@RequestMapping("/api/user")
@RequiredArgsConstructor
public class UserProfileController {
    private final UserProfileService userProfileService;
    private final UserRepository userRepository;
    private final ProblemFeedbackService problemFeedbackService;
    private final AuthService authService;

    @PostMapping("/onboarding")
    public ResponseEntity<ApiResponse<?>> completeOnboarding(Authentication authentication,
                                                             @Valid @RequestBody OnboardingRequest request) {
        User user = requireAuthenticatedUser(authentication);
        return ResponseEntity.ok(ApiResponse.success(
                "Onboarding 完成",
                UserProfileResponse.fromEntity(userProfileService.createOrUpdateUserProfile(user, request))
        ));
    }

    @GetMapping("/profile")
    public ResponseEntity<ApiResponse<?>> getUserProfile(Authentication authentication) {
        User user = requireAuthenticatedUser(authentication);
        return ResponseEntity.ok(ApiResponse.success(
                UserProfileResponse.fromEntity(
                        userProfileService.getUserProfile(user)
                                .orElseThrow(() -> new ResourceNotFoundException("尚未完成 onboarding"))
                )
        ));
    }

    @PostMapping("/problem-feedback")
    public ResponseEntity<ApiResponse<?>> createProblemFeedback(Authentication authentication,
                                                                @Valid @RequestBody ProblemFeedbackRequest request) {
        User user = requireAuthenticatedUser(authentication);
        return ResponseEntity.ok(ApiResponse.success(
                "問題回饋已送出",
                ProblemFeedbackResponse.fromEntity(problemFeedbackService.create(user, request))
        ));
    }

    @GetMapping("/problem-feedback")
    public ResponseEntity<ApiResponse<?>> listMyProblemFeedback(Authentication authentication) {
        User user = requireAuthenticatedUser(authentication);
        return ResponseEntity.ok(ApiResponse.success(
                problemFeedbackService.getByUser(user).stream()
                        .map(ProblemFeedbackResponse::fromEntity)
                        .toList()
        ));
    }

    @PostMapping("/problem-feedback/{id}/photo")
    public ResponseEntity<ApiResponse<?>> uploadProblemFeedbackPhoto(Authentication authentication,
                                                                     @PathVariable Long id,
                                                                     @RequestParam("file") MultipartFile file) throws IOException {
        User user = requireAuthenticatedUser(authentication);
        return ResponseEntity.ok(ApiResponse.success(
                "照片上傳成功",
                ProblemFeedbackResponse.fromEntity(problemFeedbackService.savePhoto(id, user, file))
        ));
    }

    @DeleteMapping("/account")
    public ResponseEntity<ApiResponse<Void>> deleteMyAccount(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new UnauthorizedException("未登入");
        }
        authService.deleteAccount(authentication.getPrincipal().toString());
        return ResponseEntity.ok(ApiResponse.success("帳號已註销", null));
    }

    private User requireAuthenticatedUser(Authentication authentication) {
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new UnauthorizedException("未登入");
        }

        return userRepository.findByEmail(authentication.getPrincipal().toString())
                .orElseThrow(() -> new UnauthorizedException("登入狀態無效"));
    }
}
