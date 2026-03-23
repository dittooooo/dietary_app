//負責：註冊帳號，檢查 email 是否已存在，密碼加密，驗證登入密碼，產生 JWT token
package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.LoginRequest;
import com.tku.dietary_app.dto.RegisterRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;//這個類別是用來做密碼加密與密碼比對
import org.springframework.stereotype.Service;//匯入 @Service

// 認證服務類別，處理用戶註冊和登入邏輯
@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final BCryptPasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;

    // 處理用戶註冊 - 自動登入並返回 Token
    public String register(RegisterRequest request) {

        if (userRepository.findByEmail(request.getEmail()).isPresent()) {
            throw new RuntimeException("已有帳號？返回登入");
        }

        User user = User.builder()
                .email(request.getEmail())
                .password(passwordEncoder.encode(request.getPassword()))
                .hasCompletedOnboarding(false)
                .build();//完成 User 物件建立

        userRepository.save(user);//把這個新的 User 存進資料庫

        // 自動登入，返回 Token
        String token = jwtUtil.generateToken(user.getEmail());

        return token;
    }

    // 處理用戶登入
    public String login(LoginRequest request) {
        //找到使用者 → 回傳 User，找不到 → 丟出錯誤
        User user = userRepository.findByEmail(request.getEmail())
                .orElseThrow(() -> new RuntimeException("尚未註冊"));

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new RuntimeException("密碼錯誤或格式不符");
        }

        String token = jwtUtil.generateToken(user.getEmail());

        return token;
    }
}