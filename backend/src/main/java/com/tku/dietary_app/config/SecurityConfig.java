package com.tku.dietary_app.config;

import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

/**
 * Spring Security 的主要設定。
 *
 * 這裡決定：
 * 1. 哪些 API 不需要登入。
 * 2. 哪些 API 需要登入。
 * 3. 哪些 API 只有管理者可以使用。
 * 4. JWT filter 要插入到 Spring Security 流程的哪個位置。
 */
@Configuration
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtFilter;

    // 配置安全過濾鏈
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {

        http
                // 後端使用 JWT，不依賴瀏覽器 session/cookie，所以關閉 CSRF。
                .csrf(csrf -> csrf.disable())

                // 每次 request 都靠 Authorization header 的 JWT 重新驗證。
                .sessionManagement(session ->
                        session.sessionCreationPolicy(SessionCreationPolicy.STATELESS)
                )

                .authorizeHttpRequests(auth -> auth
                        // 註冊與登入不需要 token。
                        .requestMatchers("/api/register", "/api/login").permitAll()

                        // 後台 API 只允許 ROLE_ADMIN 使用。
                        .requestMatchers("/api/admin/**").hasAuthority("ROLE_ADMIN")

                        // 一般使用者功能只要登入即可使用。
                        .requestMatchers("/api/onboarding").authenticated()
                        .requestMatchers("/api/user/**").authenticated()

                        // 其他沒明確列出的 API，預設都要登入。
                        .anyRequest().authenticated()
                )

                // 在 Spring Security 檢查帳號密碼前，先用 JWT 建立登入狀態。
                .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    /**
     * 密碼加密器。
     * 註冊或建立使用者時會用它把明文密碼轉成 BCrypt hash。
     */
    @Bean
    public BCryptPasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
