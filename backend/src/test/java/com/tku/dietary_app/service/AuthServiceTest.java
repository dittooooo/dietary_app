package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.AuthResponse;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.exception.UnauthorizedException;
import com.tku.dietary_app.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private BCryptPasswordEncoder passwordEncoder;

    @Mock
    private JwtUtil jwtUtil;

    @InjectMocks
    private AuthService authService;

    @Test
    void refreshRotatesTokensAndUpdatesStoredHash() {
        String oldRefreshTokenHash = hashRefreshToken("old-refresh-token");
        String newRefreshTokenHash = hashRefreshToken("new-refresh-token");

        User user = User.builder()
                .id(1L)
                .email("user@example.com")
                .password("encoded-password")
                .hasCompletedOnboarding(true)
                .refreshTokenHash(oldRefreshTokenHash)
                .refreshTokenExpiresAt(LocalDateTime.now().plusDays(1))
                .build();

        when(jwtUtil.validateRefreshToken("old-refresh-token")).thenReturn("user@example.com");
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(user));
        when(jwtUtil.generateAccessToken("user@example.com")).thenReturn("new-access-token");
        when(jwtUtil.generateRefreshToken("user@example.com")).thenReturn("new-refresh-token");
        when(jwtUtil.getAccessTokenExpirationSeconds()).thenReturn(1800L);
        when(jwtUtil.getRefreshTokenExpirationSeconds()).thenReturn(2592000L);
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

        AuthResponse response = authService.refresh("old-refresh-token");

        assertThat(response.isSuccess()).isTrue();
        assertThat(response.getAccessToken()).isEqualTo("new-access-token");
        assertThat(response.getRefreshToken()).isEqualTo("new-refresh-token");
        assertThat(response.isNeedsOnboarding()).isFalse();

        ArgumentCaptor<User> savedUserCaptor = ArgumentCaptor.forClass(User.class);
        verify(userRepository, atLeastOnce()).save(savedUserCaptor.capture());
        User savedUser = savedUserCaptor.getValue();
        assertThat(savedUser.getRefreshTokenHash()).isEqualTo(newRefreshTokenHash);
        assertThat(savedUser.getRefreshTokenExpiresAt()).isAfter(LocalDateTime.now().plusDays(29));
    }

    @Test
    void refreshRejectsBlankToken() {
        assertThatThrownBy(() -> authService.refresh("   "))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessage("缺少 refresh token");
    }

    @Test
    void refreshRejectsExpiredStoredRefreshToken() {
        User user = User.builder()
                .id(1L)
                .email("user@example.com")
                .refreshTokenHash(hashRefreshToken("old-refresh-token"))
                .refreshTokenExpiresAt(LocalDateTime.now().minusSeconds(1))
                .build();

        when(jwtUtil.validateRefreshToken("old-refresh-token")).thenReturn("user@example.com");
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(user));

        assertThatThrownBy(() -> authService.refresh("old-refresh-token"))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessage("refresh token 無效或已過期");
    }

    private static String hashRefreshToken(String refreshToken) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hashedBytes = digest.digest(refreshToken.getBytes(StandardCharsets.UTF_8));
            return Base64.getEncoder().encodeToString(hashedBytes);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }
}
