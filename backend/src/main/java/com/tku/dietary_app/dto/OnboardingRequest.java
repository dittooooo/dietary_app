package com.tku.dietary_app.dto;

import jakarta.validation.constraints.*;
import lombok.Data;
import java.util.List;
import org.hibernate.annotations.CreationTimestamp;//自動記錄資料建立時間

@Data
public class OnboardingRequest {

    @NotBlank(message = "暱稱不能為空")
    private String nickname;

    @NotBlank(message = "性別不能為空")
    private String gender;

    @NotNull(message = "年齡不能為空")
    @Min(value = 1, message = "年齡必須大於0")
    private Integer age;

    @NotNull(message = "身高不能為空")
    @Min(value = 1, message = "身高必須大於0")
    private Double height;

    @NotNull(message = "體重不能為空")
    @Min(value = 1, message = "體重必須大於0")
    private Double weight;

    @NotEmpty(message = "健康狀況不能為空")
    private List<String> healthConditions;

    @NotBlank(message = "飲食目標不能為空")
    private String dietGoal;

    @NotBlank(message = "小精靈角色不能為空")
    private String petType;
}