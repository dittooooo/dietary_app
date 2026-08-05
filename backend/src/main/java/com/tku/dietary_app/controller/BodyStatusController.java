package com.tku.dietary_app.controller;

import com.tku.dietary_app.entity.User;
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
    public ResponseEntity<?> getBodyStatus() {
        User user = getLoginUser();
        return ResponseEntity.ok(bodyStatusService.getCurrentStatus(user.getId()));
    }

    @PostMapping("/settle")
    public ResponseEntity<?> settleDailyScores() {
        User user = getLoginUser();
        return ResponseEntity.ok(bodyStatusService.settleDailyScores(user.getId()));
    }

    @PostMapping("/recalculate")
    public ResponseEntity<?> recalculateBodyMetrics() {
        User user = getLoginUser();
        return ResponseEntity.ok(bodyStatusService.recalculateBodyMetrics(user.getId()));
    }

    private User getLoginUser() {
        String email = SecurityContextHolder.getContext().getAuthentication().getPrincipal().toString();
        return userRepository.findByEmail(email).orElseThrow(() -> new RuntimeException("找不到登入使用者"));
    }
}
