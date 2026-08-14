package com.tku.dietary_app.controller;

import com.tku.dietary_app.config.JwtAuthenticationFilter;
import com.tku.dietary_app.dto.AuthResponse;
import com.tku.dietary_app.dto.LoginRequest;
import com.tku.dietary_app.dto.RefreshTokenRequest;
import com.tku.dietary_app.dto.RegisterRequest;
import com.tku.dietary_app.service.AuthService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.TestingAuthenticationToken;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(AuthController.class)
@AutoConfigureMockMvc(addFilters = false)
class AuthControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private AuthService authService;

    @MockitoBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @Test
    void registerReturnsAccessAndRefreshTokens() throws Exception {
        when(authService.register(any(RegisterRequest.class))).thenReturn(AuthResponse.builder()
                .success(true)
                .message("註冊成功")
                .tokenType("Bearer")
                .accessToken("access-token")
                .refreshToken("refresh-token")
                .accessTokenExpiresInSeconds(1800)
                .refreshTokenExpiresInSeconds(2592000)
                .needsOnboarding(true)
                .build());

        mockMvc.perform(post("/api/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "user@example.com",
                                  "password": "User123"
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.tokenType").value("Bearer"))
                .andExpect(jsonPath("$.accessToken").value("access-token"))
                .andExpect(jsonPath("$.refreshToken").value("refresh-token"))
                .andExpect(jsonPath("$.needsOnboarding").value(true));
    }

    @Test
    void loginReturnsAuthPayload() throws Exception {
        when(authService.login(any(LoginRequest.class))).thenReturn(AuthResponse.builder()
                .success(true)
                .message("登入成功")
                .tokenType("Bearer")
                .accessToken("access-token")
                .refreshToken("refresh-token")
                .accessTokenExpiresInSeconds(1800)
                .refreshTokenExpiresInSeconds(2592000)
                .needsOnboarding(false)
                .build());

        mockMvc.perform(post("/api/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "user@example.com",
                                  "password": "User123"
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.accessToken").value("access-token"))
                .andExpect(jsonPath("$.refreshToken").value("refresh-token"))
                .andExpect(jsonPath("$.needsOnboarding").value(false));
    }

    @Test
    void refreshReturnsRotatedTokens() throws Exception {
        when(authService.refresh(eq("old-refresh-token"))).thenReturn(AuthResponse.builder()
                .success(true)
                .message("權杖更新成功")
                .tokenType("Bearer")
                .accessToken("new-access-token")
                .refreshToken("new-refresh-token")
                .accessTokenExpiresInSeconds(1800)
                .refreshTokenExpiresInSeconds(2592000)
                .needsOnboarding(false)
                .build());

        mockMvc.perform(post("/api/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "refreshToken": "old-refresh-token"
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").value("new-access-token"))
                .andExpect(jsonPath("$.refreshToken").value("new-refresh-token"));
    }

    @Test
    void logoutReturnsApiResponse() throws Exception {
        doNothing().when(authService).logout(eq("user@example.com"));

        mockMvc.perform(post("/api/logout")
                        .principal(new TestingAuthenticationToken("user@example.com", null, "ROLE_USER")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.message").value("已登出"))
                .andExpect(jsonPath("$.data").doesNotExist());
    }

    @Test
    void registerWithInvalidEmailReturnsBadRequest() throws Exception {
        mockMvc.perform(post("/api/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "bad-email",
                                  "password": "User123"
                                }
                                """))
                .andExpect(status().isBadRequest());
    }
}
