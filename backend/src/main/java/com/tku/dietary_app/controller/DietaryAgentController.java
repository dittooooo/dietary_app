package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.DietaryAskRequest;
import jakarta.validation.Valid;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.UserRepository;
import com.tku.dietary_app.service.DietaryAgentService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/dietary")
@RequiredArgsConstructor
public class DietaryAgentController {

    private final DietaryAgentService dietaryAgentService;
    private final UserRepository userRepository;

    @PostMapping("/ask-weekly-analysis")
    public ResponseEntity<?> ask(@Valid @RequestBody DietaryAskRequest request) {
        String email = SecurityContextHolder.getContext().getAuthentication().getPrincipal().toString();
        User user = userRepository.findByEmail(email).orElseThrow(() -> new RuntimeException("使用者不存在"));
        return ResponseEntity.ok(dietaryAgentService.ask(user.getId(), request));
    }
}
