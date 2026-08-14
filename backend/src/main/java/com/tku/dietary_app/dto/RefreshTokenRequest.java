package com.tku.dietary_app.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

@Data
public class RefreshTokenRequest {
    @NotBlank(message = "refreshToken 為必填欄位")
    private String refreshToken;
}
