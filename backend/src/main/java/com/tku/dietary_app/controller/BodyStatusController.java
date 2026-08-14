package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.ApiResponse;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.exception.UnauthorizedException;
import com.tku.dietary_app.repository.UserRepository;
import com.tku.dietary_app.service.BodyStatusService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/body-status")
@RequiredArgsConstructor
public class BodyStatusController {
    private final BodyStatusService bodyStatusService;
    private final UserRepository userRepository;

    @GetMapping
    public ResponseEntity<ApiResponse<?>> getBodyStatus() {
        User user = getLoginUser();
        return ResponseEntity.ok(ApiResponse.success(bodyStatusService.getCurrentStatus(user.getId())));
    }

    @PostMapping("/settle")
    public ResponseEntity<ApiResponse<?>> settleDailyScores() {
        User user = getLoginUser();
        return ResponseEntity.ok(ApiResponse.success("每日結算完成", bodyStatusService.settleDailyScores(user.getId())));
    }

    @PostMapping("/recalculate")
    public ResponseEntity<ApiResponse<?>> recalculateBodyMetrics() {
        User user = getLoginUser();
        return ResponseEntity.ok(ApiResponse.success("身體指標重算完成", bodyStatusService.recalculateBodyMetrics(user.getId())));
    }

    private User getLoginUser() {
        String email = SecurityContextHolder.getContext().getAuthentication().getPrincipal().toString();
        return userRepository.findByEmail(email)
                .orElseThrow(() -> new UnauthorizedException("登入狀態無效"));
    }
}
