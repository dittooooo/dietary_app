package com.tku.dietary_app.dto;

import lombok.Data;

@Data
public class LoginRequest {
    private String email;
    private String password;
}
