package com.tku.dietary_app.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class ProblemFeedbackReplyRequest {
    @NotBlank(message = "回覆內容不可空白")
    @Size(max = 2000, message = "回覆內容不可超過 2000 字")
    private String adminReply;
}
