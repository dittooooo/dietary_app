package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.ApiResponse;
import com.tku.dietary_app.dto.ProblemFeedbackReplyRequest;
import com.tku.dietary_app.dto.ProblemFeedbackResponse;
import com.tku.dietary_app.service.ProblemFeedbackService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminController {

    private final ProblemFeedbackService problemFeedbackService;

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
