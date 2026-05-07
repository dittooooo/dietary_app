package com.tku.dietary_app.dto;

import lombok.Data;

@Data
public class AdminUserRequest {
    // 帳號部分
    private String email;
    private String password;
    private String role; // ROLE_USER 或 ROLE_ADMIN

    // 生理與健康部分 (對應你圖中的欄位)
    private String name;
    private String gender;
    private Integer age;
    private Double height;
    private Double weight;
    private String specialDisease; // 特殊疾病
    private String dietGoal;       // 目標
    private String dietaryHistory; // 過去飲食
    private String petType;
}