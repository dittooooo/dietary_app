package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.LoginRequest;
import com.tku.dietary_app.dto.RegisterRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;

// 認證服務類別，處理用戶註冊和登入邏輯
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

        User user = User.builder()
                .email(request.getEmail())
                .password(passwordEncoder.encode(request.getPassword()))
                .build();

        userRepository.save(user);

        return "註冊成功";
    }

    // 處理用戶登入
    public String login(LoginRequest request) {

        User user = userRepository.findByEmail(request.getEmail())
                .orElseThrow(() -> new RuntimeException("尚未註冊"));

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new RuntimeException("密碼錯誤或格式不符");
        }

        String token = jwtUtil.generateToken(user.getEmail());

        return token;
    }
}