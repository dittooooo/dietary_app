package com.tku.dietary_app.config;

import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 系統啟動時建立預設管理者帳號。
 *
 * 目的：
 * 1. 第一次啟動專案時，不需要手動進資料庫建立 admin。
 * 2. 如果 admin@gmail.com 已存在，會確保它仍然是 ROLE_ADMIN。
 *
 * 預設值可以用環境變數覆蓋：
 * ADMIN_EMAIL=admin@gmail.com
 * ADMIN_PASSWORD=Admin123
 */
@Component
@RequiredArgsConstructor
public class DefaultAdminInitializer implements CommandLineRunner {

    private static final String ADMIN_ROLE = "ROLE_ADMIN";

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    @Value("${ADMIN_EMAIL:admin@gmail.com}")
    private String adminEmail;

    @Value("${ADMIN_PASSWORD:Admin123}")
    private String adminPassword;

    @Override
    @Transactional
    public void run(String... args) {
        userRepository.findByEmail(adminEmail)
                .ifPresentOrElse(this::ensureAdminRole, this::createDefaultAdmin);
    }

    private void ensureAdminRole(User user) {
        if (!ADMIN_ROLE.equals(user.getRole())) {
            user.setRole(ADMIN_ROLE);
            userRepository.save(user);
        }
    }

    private void createDefaultAdmin() {
        User admin = User.builder()
                .email(adminEmail)
                .password(passwordEncoder.encode(adminPassword))
                .role(ADMIN_ROLE)
                .hasCompletedOnboarding(true)
                .build();

        userRepository.save(admin);
    }
}
