package com.tku.dietary_app.config;

import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
@Profile({"local", "dev"})
@ConditionalOnProperty(prefix = "app.admin.bootstrap", name = "enabled", havingValue = "true")
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
        String normalizedAdminEmail = adminEmail.trim().toLowerCase();
        userRepository.findByEmailIgnoreCase(normalizedAdminEmail)
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
                .email(adminEmail.trim().toLowerCase())
                .password(passwordEncoder.encode(adminPassword))
                .role(ADMIN_ROLE)
                .hasCompletedOnboarding(true)
                .build();

        userRepository.save(admin);
    }
}
