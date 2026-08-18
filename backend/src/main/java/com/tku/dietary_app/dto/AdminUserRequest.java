package com.tku.dietary_app.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.time.LocalDate;

@Data
public class AdminUserRequest {
    @NotBlank(message = "email 為必填欄位")
    @Email(message = "email 格式不正確")
    private String email;

    @Pattern(regexp = "^(|.{8,})$", message = "password 至少需要 8 個字元")
    private String password;

    @NotBlank(message = "role 為必填欄位")
    @Pattern(regexp = "^(?i:(ROLE_USER|ROLE_ADMIN|USER|ADMIN))$", message = "role 只允許 USER 或 ADMIN")
    private String role;

    @NotBlank(message = "name 為必填欄位")
    @Size(max = 100, message = "name 長度不可超過 100")
    private String name;

    @NotBlank(message = "gender 為必填欄位")
    @Size(max = 20, message = "gender 長度不可超過 20")
    private String gender;

    @NotNull(message = "birthDate 為必填欄位")
    private LocalDate birthDate;

    @NotNull(message = "height 為必填欄位")
    @DecimalMin(value = "0.1", message = "height 必須大於 0")
    private Double height;

    @NotNull(message = "weight 為必填欄位")
    @DecimalMin(value = "0.1", message = "weight 必須大於 0")
    private Double weight;

    @NotBlank(message = "specialDisease 為必填欄位")
    private String specialDisease;

    @NotBlank(message = "dietGoal 為必填欄位")
    private String dietGoal;

    @Size(max = 1000, message = "dietaryHistory 長度不可超過 1000")
    private String dietaryHistory;

    @NotBlank(message = "petType 為必填欄位")
    private String petType;
}
