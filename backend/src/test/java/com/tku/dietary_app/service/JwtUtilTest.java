package com.tku.dietary_app.service;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JwtUtilTest {

    private final JwtUtil jwtUtil = new JwtUtil(
            "01234567890123456789012345678901",
            1800L,
            2592000L
    );

    @Test
    void validateAccessTokenReturnsSubject() {
        String token = jwtUtil.generateAccessToken("user@example.com");

        String subject = jwtUtil.validateAccessToken(token);

        assertThat(subject).isEqualTo("user@example.com");
    }

    @Test
    void refreshTokenCannotBeUsedAsAccessToken() {
        String refreshToken = jwtUtil.generateRefreshToken("user@example.com");

        assertThatThrownBy(() -> jwtUtil.validateAccessToken(refreshToken))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("token type 不符");
    }

    @Test
    void accessTokenCannotBeUsedAsRefreshToken() {
        String accessToken = jwtUtil.generateAccessToken("user@example.com");

        assertThatThrownBy(() -> jwtUtil.validateRefreshToken(accessToken))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("token type 不符");
    }
}
