package com.tku.dietary_app.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class RegisterRequest {

    @NotBlank(message = "請輸入電子郵件")
    @Pattern(regexp = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,6}$",message = "電子郵件格式不正確")
    private String email;

    @NotBlank(message = "請輸入密碼")
    @Size(min = 6, max = 18, message = "長度需為 6-18 位")
    @Pattern(regexp = ".*[a-z].*", message = "密碼必須包含小寫英文字母")
    @Pattern(regexp = ".*[A-Z].*", message = "密碼必須包含大寫英文字母")
    private String password;

}