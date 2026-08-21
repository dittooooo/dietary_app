package com.tku.dietary_app.dto;

import com.tku.dietary_app.entity.ProblemFeedback;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ProblemFeedbackResponse {
    private Long id;
    private Long userId;
    private String userName;
    private String content;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public static ProblemFeedbackResponse fromEntity(ProblemFeedback feedback) {
        return ProblemFeedbackResponse.builder()
                .id(feedback.getId())
                .userId(feedback.getUser() == null ? null : feedback.getUser().getId())
                .userName(feedback.getUserName())
                .content(feedback.getContent())
                .createdAt(feedback.getCreatedAt())
                .updatedAt(feedback.getUpdatedAt())
                .build();
    }
}
