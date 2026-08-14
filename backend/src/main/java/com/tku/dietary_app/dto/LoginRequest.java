package com.tku.dietary_app.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class LoginRequest {

    @NotBlank(message = "email 為必填欄位")
    @Pattern(regexp = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,6}$", message = "email 格式不正確")
    private String email;

    @NotBlank(message = "password 為必填欄位")
    @Size(min = 6, max = 18, message = "password 長度需介於 6 到 18 個字元")
    @Pattern(regexp = ".*[a-z].*", message = "password 至少需要一個小寫字母")
    @Pattern(regexp = ".*[A-Z].*", message = "password 至少需要一個大寫字母")
    @Pattern(regexp = ".*[0-9].*", message = "password 至少需要一個數字")
    private String password;
}
