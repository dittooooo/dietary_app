package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.AuthResponse;
import com.tku.dietary_app.dto.LoginRequest;
import com.tku.dietary_app.dto.RegisterRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.exception.UnauthorizedException;
import com.tku.dietary_app.repository.DietRecordRepository;
import com.tku.dietary_app.repository.ProblemFeedbackRepository;
import com.tku.dietary_app.repository.UserProfileRepository;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.Base64;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final UserProfileRepository userProfileRepository;
    private final DietRecordRepository dietRecordRepository;
    private final ProblemFeedbackRepository problemFeedbackRepository;
    private final BCryptPasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;

    @Transactional
    public AuthResponse register(RegisterRequest request) {
        String normalizedEmail = request.getEmail().trim().toLowerCase();
        if (userRepository.findByEmail(normalizedEmail).isPresent()) {
            throw new IllegalArgumentException("Email 已被註冊");
        }

        User user = User.builder()
                .email(normalizedEmail)
                .password(passwordEncoder.encode(request.getPassword()))
                .hasCompletedOnboarding(false)
                .build();

        userRepository.save(user);
        return issueTokens(user, "註冊成功", true);
    }

    @Transactional
    public AuthResponse login(LoginRequest request) {
        User user = userRepository.findByEmail(request.getEmail().trim().toLowerCase())
                .orElseThrow(() -> new BadCredentialsException("帳號或密碼錯誤"));

        ensureUserEnabled(user);

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new BadCredentialsException("帳號或密碼錯誤");
        }

        return issueTokens(user, "登入成功", !Boolean.TRUE.equals(user.getHasCompletedOnboarding()));
    }

    @Transactional
    public AuthResponse refresh(String refreshToken) {
        String normalizedRefreshToken = refreshToken == null ? "" : refreshToken.trim();
        if (normalizedRefreshToken.isBlank()) {
            throw new UnauthorizedException("缺少 refresh token");
        }

        String email = jwtUtil.validateRefreshToken(normalizedRefreshToken);

        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new UnauthorizedException("refresh token 無效"));

        ensureUserEnabled(user);

        if (user.getRefreshTokenHash() == null
                || user.getRefreshTokenExpiresAt() == null
                || user.getRefreshTokenExpiresAt().isBefore(LocalDateTime.now())
                || !hashRefreshToken(normalizedRefreshToken).equals(user.getRefreshTokenHash())) {
            throw new UnauthorizedException("refresh token 無效或已過期");
        }

        return issueTokens(user, "權杖更新成功", !Boolean.TRUE.equals(user.getHasCompletedOnboarding()));
    }

    @Transactional
    public void logout(String email) {
        User user = userRepository.findByEmail(email.trim().toLowerCase())
                .orElseThrow(() -> new UnauthorizedException("登入狀態無效"));
        user.setRefreshTokenHash(null);
        user.setRefreshTokenExpiresAt(null);
        userRepository.save(user);
    }

    @Transactional
    public void deleteAccount(String email) {
        User user = userRepository.findByEmail(email.trim().toLowerCase())
                .orElseThrow(() -> new UnauthorizedException("登入狀態無效"));

        dietRecordRepository.deleteByUserId(user.getId());
        problemFeedbackRepository.deleteByUserId(user.getId());
        dietRecordRepository.flush();
        problemFeedbackRepository.flush();

        userProfileRepository.findByUser(user)
                .ifPresent(profile -> {
                    userProfileRepository.delete(profile);
                    userProfileRepository.flush();
                });

        userRepository.delete(user);
        userRepository.flush();
    }

    private AuthResponse issueTokens(User user, String message, boolean needsOnboarding) {
        String accessToken = jwtUtil.generateAccessToken(user.getEmail());
        String refreshToken = jwtUtil.generateRefreshToken(user.getEmail());

        user.setRefreshTokenHash(hashRefreshToken(refreshToken));
        user.setRefreshTokenExpiresAt(LocalDateTime.now().plusSeconds(jwtUtil.getRefreshTokenExpirationSeconds()));
        userRepository.save(user);

        return AuthResponse.builder()
                .success(true)
                .message(message)
                .role(user.getRole())
                .tokenType("Bearer")
                .accessToken(accessToken)
                .refreshToken(refreshToken)
                .accessTokenExpiresInSeconds(jwtUtil.getAccessTokenExpirationSeconds())
                .refreshTokenExpiresInSeconds(jwtUtil.getRefreshTokenExpirationSeconds())
                .needsOnboarding(needsOnboarding)
                .build();
    }

    private void ensureUserEnabled(User user) {
        if (Boolean.FALSE.equals(user.getEnabled())) {
            throw new UnauthorizedException("帳號已被禁用，請聯絡管理者");
        }
    }

    private String hashRefreshToken(String refreshToken) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hashedBytes = digest.digest(refreshToken.getBytes(StandardCharsets.UTF_8));
            return Base64.getEncoder().encodeToString(hashedBytes);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }
}
