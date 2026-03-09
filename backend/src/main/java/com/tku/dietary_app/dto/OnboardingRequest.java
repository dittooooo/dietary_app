package com.tku.dietary_app.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotEmpty;
import java.util.List;

// Onboarding 請求資料傳輸物件，包含用戶個人資料的欄位
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

    // Constructors
    public OnboardingRequest() {}

    public OnboardingRequest(String nickname, String gender, Integer age, Double height,
                            Double weight, List<String> healthConditions, String dietGoal, String petType) {
        this.nickname = nickname;
        this.gender = gender;
        this.age = age;
        this.height = height;
        this.weight = weight;
        this.healthConditions = healthConditions;
        this.dietGoal = dietGoal;
        this.petType = petType;
    }

    // Getters and Setters
    public String getNickname() { return nickname; }
    public void setNickname(String nickname) { this.nickname = nickname; }

    public String getGender() { return gender; }
    public void setGender(String gender) { this.gender = gender; }

    public Integer getAge() { return age; }
    public void setAge(Integer age) { this.age = age; }

    public Double getHeight() { return height; }
    public void setHeight(Double height) { this.height = height; }

    public Double getWeight() { return weight; }
    public void setWeight(Double weight) { this.weight = weight; }

    public List<String> getHealthConditions() { return healthConditions; }
    public void setHealthConditions(List<String> healthConditions) { this.healthConditions = healthConditions; }

    public String getDietGoal() { return dietGoal; }
    public void setDietGoal(String dietGoal) { this.dietGoal = dietGoal; }

    public String getPetType() { return petType; }
    public void setPetType(String petType) { this.petType = petType; }
}
