package com.tku.dietary_app.config;

import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.UserRepository;
import com.tku.dietary_app.service.JwtUtil;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * 每次 API request 進來時，都會先經過這個 filter。
 *
 * 流程：
 * 1. 從 Authorization header 取出 Bearer token。
 * 2. 驗證 JWT 並解析出 email。
 * 3. 用 email 查資料庫，取得使用者角色 role。
 * 4. 把 email 與 role 放進 Spring Security 的登入狀態。
 */
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtUtil jwtUtil;
    private final UserRepository userRepository;

    // 過濾每個請求，檢查 JWT Token
    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {

        final String authHeader = request.getHeader("Authorization");

        // 沒有 token 的 request 先放行，後續 SecurityConfig 會判斷是否允許匿名存取。
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            filterChain.doFilter(request, response);
            return;
        }

        String token = authHeader.substring(7);

        try {
            String email = jwtUtil.validateAccessToken(token);
            User user = userRepository.findByEmail(email).orElseThrow();
            String role = normalizeRole(user.getRole());

            UsernamePasswordAuthenticationToken authentication = new UsernamePasswordAuthenticationToken(
                    email,
                    null,
                    List.of(new SimpleGrantedAuthority(role))
            );

            // 這行設定完成後，Controller 和 SecurityConfig 都能知道目前登入者與權限。
            SecurityContextHolder.getContext().setAuthentication(authentication);

        } catch (Exception e) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            return;
        }

        filterChain.doFilter(request, response);
    }

    /**
     * Spring Security 慣例是 ROLE_ADMIN / ROLE_USER。
     * 這裡允許資料庫填 ADMIN、admin、ROLE_ADMIN，最後都轉成 ROLE_ADMIN。
     */
    private String normalizeRole(String role) {
        if (role == null || role.isBlank()) {
            return "ROLE_USER";
        }

        String normalizedRole = role.trim().toUpperCase();
        return normalizedRole.startsWith("ROLE_") ? normalizedRole : "ROLE_" + normalizedRole;
    }
}
