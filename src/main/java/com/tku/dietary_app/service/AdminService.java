package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.AdminUserRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.repository.UserRepository;
import com.tku.dietary_app.repository.UserProfileRepository;
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

    // 查：取得所有使用者清單
    public List<UserProfile> getAllUsers() {
        return userProfileRepository.findAll();
    }

    // 查：單筆查詢
    public UserProfile getUserById(Long id) {
        return userProfileRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到該使用者 (ID: " + id + ")"));
    }

    // 搜：按關鍵字查詢
    public List<UserProfile> searchUsers(String keyword) {
        return userProfileRepository.searchUsers(keyword);
    }

    // 增：新增使用者
    @Transactional
    public UserProfile createUser(AdminUserRequest request) {
        // 1. 建立並儲存基礎帳號 (User)
        User user = User.builder()
                .email(request.getEmail())
                .password(passwordEncoder.encode(request.getPassword()))
                .role(request.getRole() != null ? request.getRole() : "ROLE_USER")
                .hasCompletedOnboarding(true)
                .build();
        User savedUser = userRepository.save(user);

        // 2. 建立並儲存個人詳細資料 (UserProfile)
        UserProfile profile = UserProfile.builder()
                .user(savedUser)
                .nickname(request.getName()) // DTO 的 name 存入 nickname
                .gender(request.getGender())
                .age(request.getAge())
                .height(request.getHeight())
                .weight(request.getWeight())
                .healthConditions(request.getSpecialDisease())
                .dietGoal(request.getDietGoal())
                .dietHistory(request.getDietaryHistory()) // 新增過去飲食
                .petType(request.getPetType() != null ? request.getPetType() : "None")
                .build();
        return userProfileRepository.save(profile);
    }

    // 改：編輯使用者資料
    @Transactional
    public UserProfile updateUser(Long id, AdminUserRequest request) {
        // 透過 UserProfile ID 找到該筆資料
        UserProfile profile = userProfileRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("使用者個人資料不存在"));

        // 更新詳細資料欄位
        profile.setNickname(request.getName());
        profile.setGender(request.getGender());
        profile.setAge(request.getAge());
        profile.setHeight(request.getHeight());
        profile.setWeight(request.getWeight());
        profile.setHealthConditions(request.getSpecialDisease());
        profile.setDietGoal(request.getDietGoal());
        profile.setDietHistory(request.getDietaryHistory()); // 新增過去飲食

        if (request.getPetType() != null) {
            profile.setPetType(request.getPetType());
        }

        // 處理密碼更新 (如果 request 有密碼才更新)
        if (request.getPassword() != null && !request.getPassword().isEmpty()) {
            User user = profile.getUser();
            user.setPassword(passwordEncoder.encode(request.getPassword()));
            userRepository.save(user);
        }

        return userProfileRepository.save(profile);
    }

    // 刪：刪除使用者 (修正版，解決 FOREIGN KEY 衝突)
    @Transactional
    public void deleteUser(Long id) {
        // 1. 找到 UserProfile
        UserProfile profile = userProfileRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到該個人資料 (ID: " + id + ")"));

        // 2. 獲取關聯的 User 對象
        User user = profile.getUser();

        // 3. 執行刪除順序：先刪除子表 (UserProfile)，再刪除父表 (User)
        // 這樣可以避免資料庫 Constraint Violation 錯誤
        userProfileRepository.delete(profile);

        if (user != null) {
            userRepository.delete(user);
        }
    }
}