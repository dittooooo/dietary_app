package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.LoginRequest;
import com.tku.dietary_app.dto.RegisterRequest;
import com.tku.dietary_app.service.AuthService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

/**
 * 認證相關控制器 (Authentication Controller)
 * 負責處理使用者的註冊與登入流程
 */
@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;

    /**
     * [POST] 使用者註冊
     * * @param request 包含 email, password 的 JSON 物件
     * @return 註冊成功訊息 (String)
     * * 前端注意：
     * 1. 需符合 RegisterRequest 中的欄位驗證 (如 Email 格式)。
     * 2. 成功時回傳 "Register Success"。
     * 3. 失敗時會根據異常回傳錯誤訊息。
     */
    @PostMapping("/register")
    public String register(@Valid @RequestBody RegisterRequest request) {
        return authService.register(request);
    }

    /**
     * [POST] 使用者登入
     * * @param request 包含 email, password 的 JSON 物件
     * @return 成功登入後核發的 JWT Token (String)
     * * 前端注意：
     * 1. 登入成功後請將回傳的 Token 儲存於 localStorage 或 Cookie。
     * 2. 後續需要權限的請求，需在 Header 帶上：Authorization: Bearer <Token>。
     */
    @PostMapping("/login")
    public String login(@RequestBody LoginRequest request) {
        return authService.login(request);
    }


}
