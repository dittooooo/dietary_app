package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.AdminUserRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.exception.ResourceNotFoundException;
import com.tku.dietary_app.repository.UserProfileRepository;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
public class AdminService {

    private final UserRepository userRepository;
    private final UserProfileRepository userProfileRepository;
    private final PasswordEncoder passwordEncoder;
    private final BodyMetricsService bodyMetricsService;

    public List<UserProfile> getAllUsers() {
        return userProfileRepository.findAll();
    }

    public UserProfile getUserById(Long id) {
        return userProfileRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("找不到使用者資料 (ID: " + id + ")"));
    }

    public List<UserProfile> searchUsers(String keyword) {
        return userProfileRepository.searchUsers(keyword);
    }

    @Transactional
    public UserProfile createUser(AdminUserRequest request) {
        if (request.getPassword() == null || request.getPassword().isBlank()) {
            throw new IllegalArgumentException("管理員新增使用者時必須提供密碼");
        }

        String normalizedEmail = normalizeEmail(request.getEmail());
        userRepository.findByEmailIgnoreCase(normalizedEmail)
                .ifPresent(existingUser -> {
                    throw new IllegalArgumentException("Email 已被使用");
                });

        User user = User.builder()
                .email(normalizedEmail)
                .password(passwordEncoder.encode(request.getPassword()))
                .role(normalizeRole(request.getRole()))
                .hasCompletedOnboarding(true)
                .build();

        User savedUser = userRepository.save(user);

        UserProfile profile = UserProfile.builder()
                .user(savedUser)
                .nickname(request.getName().trim())
                .gender(request.getGender().trim())
                .age(request.getAge())
                .height(request.getHeight())
                .weight(request.getWeight())
                .healthConditions(request.getSpecialDisease().trim())
                .dietGoal(request.getDietGoal().trim())
                .petType(request.getPetType().trim())
                .build();
        bodyMetricsService.recalculateAndApply(profile);

        return userProfileRepository.save(profile);
    }

    @Transactional
    public UserProfile updateUser(Long id, AdminUserRequest request) {
        UserProfile profile = userProfileRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("找不到要更新的使用者資料"));

        String normalizedEmail = normalizeEmail(request.getEmail());

        profile.setNickname(request.getName().trim());
        profile.setGender(request.getGender().trim());
        profile.setAge(request.getAge());
        profile.setHeight(request.getHeight());
        profile.setWeight(request.getWeight());
        profile.setHealthConditions(request.getSpecialDisease().trim());
        profile.setDietGoal(request.getDietGoal().trim());
        profile.setPetType(request.getPetType().trim());
        bodyMetricsService.recalculateAndApply(profile);

        User user = profile.getUser();
        userRepository.findByEmailIgnoreCase(normalizedEmail)
                .filter(existingUser -> !existingUser.getId().equals(user.getId()))
                .ifPresent(existingUser -> {
                    throw new IllegalArgumentException("Email 已被使用");
                });

        user.setEmail(normalizedEmail);
        user.setRole(normalizeRole(request.getRole()));

        if (request.getPassword() != null && !request.getPassword().isBlank()) {
            user.setPassword(passwordEncoder.encode(request.getPassword()));
        }

        userRepository.save(user);
        return userProfileRepository.save(profile);
    }

    @Transactional
    public void deleteUser(Long id) {
        UserProfile profile = userProfileRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("找不到要刪除的使用者資料 (ID: " + id + ")"));

        User user = profile.getUser();
        userProfileRepository.delete(profile);

        if (user != null) {
            userRepository.delete(user);
        }
    }

    private String normalizeRole(String role) {
        String normalizedRole = role.trim().toUpperCase();
        return normalizedRole.startsWith("ROLE_") ? normalizedRole : "ROLE_" + normalizedRole;
    }

    private String normalizeEmail(String email) {
        return email.trim().toLowerCase();
    }
}
