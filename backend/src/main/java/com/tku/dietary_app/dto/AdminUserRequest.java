package com.tku.dietary_app.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDate;

@Getter
@Setter
public class AdminUserRequest {

    @NotBlank(message = "Email 不得為空")
    @Email(message = "Email 格式不正確")
    private String email;

    private String password;

    @NotBlank(message = "角色不得為空")
    private String role;

    @NotBlank(message = "姓名不得為空")
    private String name;

    @NotBlank(message = "性別不得為空")
    private String gender;

    @NotNull(message = "生日不得為空")
    private LocalDate birthDate;

    @NotNull(message = "身高不得為空")
    @Positive(message = "身高必須為正數")
    private Double height;

    @NotNull(message = "體重不得為空")
    @Positive(message = "體重必須為正數")
    private Double weight;

    @NotBlank(message = "特殊疾病欄位不得為空（無則填無）")
    private String specialDisease;

    @NotBlank(message = "飲食目標不得為空")
    private String dietGoal;

    @NotBlank(message = "寵物類型不得為空")
    private String petType;
}
