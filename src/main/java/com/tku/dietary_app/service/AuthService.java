package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.LoginRequest;
import com.tku.dietary_app.dto.RegisterRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final BCryptPasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;

    // 處理用戶註冊
    public String register(RegisterRequest request) {
        if (userRepository.findByEmail(request.getEmail()).isPresent()) {
            throw new RuntimeException("已有帳號？返回登入");
        }

        // 🏆 修正點 1：註冊時必須給予預設角色 "ROLE_USER"
        User user = User.builder()
                .email(request.getEmail())
                .password(passwordEncoder.encode(request.getPassword()))
                .role("ROLE_USER") // 確保新帳號都有基本權限
                .hasCompletedOnboarding(false)
                .build();

        userRepository.save(user);

        // 🏆 修正點 2：產生 Token 時要傳入 Role
        return jwtUtil.generateToken(user.getEmail(), user.getRole());
    }

    // 處理用戶登入
    public String login(LoginRequest request) {
        User user = userRepository.findByEmail(request.getEmail())
                .orElseThrow(() -> new RuntimeException("尚未註冊"));

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new RuntimeException("密碼錯誤或格式不符");
        }

        // 🏆 修正點 3：登入時也要把資料庫抓到的 Role 塞進 Token
        // 這樣管理員登入時，Token 才會帶有 "ROLE_ADMIN"
        return jwtUtil.generateToken(user.getEmail(), user.getRole());
    }
}