package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.AdminUserRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.repository.UserProfileRepository;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * 後台管理服務。
 *
 * AdminController 只負責接 API request，真正的新增、查詢、修改、刪除邏輯放在這裡。
 * 這個 service 主要管理兩張表：
 * 1. users：登入帳號、密碼、角色。
 * 2. user_profile：使用者基本資料。
 */
@Service
@RequiredArgsConstructor
public class AdminService {

    private final UserRepository userRepository;
    private final UserProfileRepository userProfileRepository;
    private final PasswordEncoder passwordEncoder;

    public List<UserProfile> getAllUsers() {
        return userProfileRepository.findAll();
    }

    public UserProfile getUserById(Long id) {
        return userProfileRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到使用者資料 (ID: " + id + ")"));
    }

    public List<UserProfile> searchUsers(String keyword) {
        return userProfileRepository.searchUsers(keyword);
    }

    /**
     * 後台新增使用者。
     *
     * 因為登入資訊和個人資料分成兩張表，所以這裡會先建立 User，
     * 再用剛建立好的 User 建立 UserProfile。
     */
    @Transactional
    public UserProfile createUser(AdminUserRequest request) {
        User user = User.builder()
                .email(request.getEmail())
                .password(passwordEncoder.encode(request.getPassword()))
                .role(normalizeRole(request.getRole()))
                .hasCompletedOnboarding(true)
                .build();

        User savedUser = userRepository.save(user);

        UserProfile profile = UserProfile.builder()
                .user(savedUser)
                .nickname(request.getName())
                .gender(request.getGender())
                .age(request.getAge())
                .height(request.getHeight())
                .weight(request.getWeight())
                .healthConditions(request.getSpecialDisease())
                .dietGoal(request.getDietGoal())
                .petType(request.getPetType() != null ? request.getPetType() : "None")
                .build();

        return userProfileRepository.save(profile);
    }

    /**
     * 後台修改使用者資料。
     *
     * 密碼和角色屬於 users 表，所以要透過 profile.getUser() 取得 User 後再更新。
     * password 留空時代表不改密碼。
     * role 留空時代表不改角色。
     */
    @Transactional
    public UserProfile updateUser(Long id, AdminUserRequest request) {
        UserProfile profile = userProfileRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到使用者個人資料"));

        profile.setNickname(request.getName());
        profile.setGender(request.getGender());
        profile.setAge(request.getAge());
        profile.setHeight(request.getHeight());
        profile.setWeight(request.getWeight());
        profile.setHealthConditions(request.getSpecialDisease());
        profile.setDietGoal(request.getDietGoal());

        if (request.getPetType() != null) {
            profile.setPetType(request.getPetType());
        }

        User user = profile.getUser();

        if (request.getPassword() != null && !request.getPassword().isEmpty()) {
            user.setPassword(passwordEncoder.encode(request.getPassword()));
            userRepository.save(user);
        }

        if (request.getRole() != null && !request.getRole().isBlank()) {
            user.setRole(normalizeRole(request.getRole()));
            userRepository.save(user);
        }

        return userProfileRepository.save(profile);
    }

    /**
     * 刪除使用者時先刪 user_profile，再刪 users。
     * 這樣可以避免資料庫外鍵關聯導致刪除失敗。
     */
    @Transactional
    public void deleteUser(Long id) {
        UserProfile profile = userProfileRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到使用者個人資料 (ID: " + id + ")"));

        User user = profile.getUser();
        userProfileRepository.delete(profile);

        if (user != null) {
            userRepository.delete(user);
        }
    }

    /**
     * role 統一存成 ROLE_USER / ROLE_ADMIN。
     * 例如前端傳 ADMIN、admin、ROLE_ADMIN，最後都會轉成 ROLE_ADMIN。
     */
    private String normalizeRole(String role) {
        if (role == null || role.isBlank()) {
            return "ROLE_USER";
        }

        String normalizedRole = role.trim().toUpperCase();
        return normalizedRole.startsWith("ROLE_") ? normalizedRole : "ROLE_" + normalizedRole;
    }
}
