package com.tku.dietary_app.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import lombok.Data;

import java.util.List;

@Data
public class OnboardingRequest {

    @NotBlank(message = "nickname 為必填欄位")
    private String nickname;

    @NotBlank(message = "gender 為必填欄位")
    private String gender;

    @NotNull(message = "age 為必填欄位")
    @Min(value = 1, message = "age 必須大於 0")
    private Integer age;

    @NotNull(message = "height 為必填欄位")
    @Min(value = 1, message = "height 必須大於 0")
    private Double height;

    @NotNull(message = "weight 為必填欄位")
    @Min(value = 1, message = "weight 必須大於 0")
    private Double weight;

    @NotEmpty(message = "healthConditions 至少要提供一項")
    private List<String> healthConditions;

    @NotBlank(message = "dietGoal 為必填欄位")
    private String dietGoal;

    @NotBlank(message = "petType 為必填欄位")
    private String petType;
}
