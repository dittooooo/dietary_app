package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.ApiResponse;
import com.tku.dietary_app.dto.DietaryAskRequest;
import com.tku.dietary_app.dto.DietaryDishNutritionRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.exception.ResourceNotFoundException;
import com.tku.dietary_app.repository.UserRepository;
import com.tku.dietary_app.service.DietaryAgentService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/dietary-agent")
@RequiredArgsConstructor
public class DietaryAgentController {

    private final DietaryAgentService dietaryAgentService;
    private final UserRepository userRepository;

    @PostMapping("/ask")
    public ResponseEntity<ApiResponse<?>> ask(
            @Valid @RequestBody DietaryAskRequest request,
            @RequestHeader(value = "X-Trace-Id", required = false) String traceId) {
        String email = SecurityContextHolder.getContext().getAuthentication().getPrincipal().toString();

        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new ResourceNotFoundException("找不到登入使用者"));

        return ResponseEntity.ok(ApiResponse.success(dietaryAgentService.ask(user.getId(), request, traceId)));
    }

    @PostMapping("/dish-nutrition")
    public ResponseEntity<ApiResponse<?>> dishNutrition(
            @Valid @RequestBody DietaryDishNutritionRequest request,
            @RequestHeader(value = "X-Trace-Id", required = false) String traceId) {
        return ResponseEntity.ok(ApiResponse.success(dietaryAgentService.dishNutrition(request, traceId)));
    }
}
