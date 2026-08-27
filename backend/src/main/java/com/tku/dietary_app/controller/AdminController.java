package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.AdminUserRequest;
import com.tku.dietary_app.dto.ApiResponse;
import com.tku.dietary_app.dto.ProblemFeedbackReplyRequest;
import com.tku.dietary_app.dto.ProblemFeedbackResponse;
import com.tku.dietary_app.dto.UserProfileResponse;
import com.tku.dietary_app.service.AdminService;
import com.tku.dietary_app.service.ProblemFeedbackService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
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
import java.security.Principal;
import java.util.Map;

@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminController {

    private final AdminService adminService;
    private final ProblemFeedbackService problemFeedbackService;

    // ── 使用者管理 ──────────────────────────────────────────────────────────────

    @GetMapping("/users")
    public ResponseEntity<ApiResponse<?>> listUsers(@RequestParam(required = false) String keyword) {
        if (keyword != null) {
            return ResponseEntity.ok(ApiResponse.success(
                    adminService.searchUsers(keyword).stream()
                            .map(UserProfileResponse::fromEntity)
                            .toList()
            ));
        }
        return ResponseEntity.ok(ApiResponse.success(
                adminService.getAllUsers().stream()
                        .map(UserProfileResponse::fromEntity)
                        .toList()
        ));
    }

    @GetMapping("/users/{id}")
    public ResponseEntity<ApiResponse<?>> getUser(@PathVariable Long id) {
        return ResponseEntity.ok(ApiResponse.success(UserProfileResponse.fromEntity(adminService.getUserById(id))));
    }

    @PostMapping("/users")
    public ResponseEntity<ApiResponse<?>> addUser(@Valid @RequestBody AdminUserRequest request) {
        return ResponseEntity.ok(ApiResponse.success(
                "使用者建立成功",
                UserProfileResponse.fromEntity(adminService.createUser(request))
        ));
    }

    @PutMapping("/users/{id}")
    public ResponseEntity<ApiResponse<?>> editUser(@PathVariable Long id, @Valid @RequestBody AdminUserRequest request) {
        return ResponseEntity.ok(ApiResponse.success(
                "使用者更新成功",
                UserProfileResponse.fromEntity(adminService.updateUser(id, request))
        ));
    }

    @PutMapping("/users/{id}/status")
    public ResponseEntity<ApiResponse<?>> updateUserStatus(@PathVariable Long id,
                                                           @RequestBody Map<String, Boolean> request,
                                                           Principal principal) {
        Boolean requestedEnabled = request.get("enabled");
        if (requestedEnabled == null) {
            throw new IllegalArgumentException("缺少 enabled 狀態");
        }

        boolean enabled = Boolean.TRUE.equals(requestedEnabled);
        return ResponseEntity.ok(ApiResponse.success(
                enabled ? "使用者已啟用" : "使用者已禁用",
                UserProfileResponse.fromEntity(adminService.setUserEnabled(id, enabled, principal.getName()))
        ));
    }

    @DeleteMapping("/users/{id}")
    public ResponseEntity<ApiResponse<Void>> removeUser(@PathVariable Long id) {
        adminService.deleteUser(id);
        return ResponseEntity.ok(ApiResponse.success("使用者刪除成功", null));
    }

    // ── 問題回饋管理 ────────────────────────────────────────────────────────────

    @GetMapping("/problem-feedback")
    public ResponseEntity<ApiResponse<?>> listProblemFeedback() {
        return ResponseEntity.ok(ApiResponse.success(
                problemFeedbackService.getAll().stream()
                        .map(ProblemFeedbackResponse::fromEntity)
                        .toList()
        ));
    }

    @PutMapping("/problem-feedback/{id}/reply")
    public ResponseEntity<ApiResponse<?>> replyProblemFeedback(@PathVariable Long id,
                                                               @Valid @RequestBody ProblemFeedbackReplyRequest request) {
        return ResponseEntity.ok(ApiResponse.success(
                "回覆已送出",
                ProblemFeedbackResponse.fromEntity(problemFeedbackService.reply(id, request))
        ));
    }
}
