package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.OnboardingRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.repository.UserProfileRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

@Service
public class UserProfileService {
    @Autowired
    private UserProfileRepository userProfileRepository;

    // 創建或更新用戶個人資料
    @Transactional
    public UserProfile createOrUpdateUserProfile(User user, OnboardingRequest request) {
        Optional<UserProfile> existingProfile = userProfileRepository.findByUser(user);

        UserProfile userProfile;
        if (existingProfile.isPresent()) {
            userProfile = existingProfile.get();
        } else {
            userProfile = new UserProfile();
            userProfile.setUser(user);
        }

        userProfile.setNickname(request.getNickname());
        userProfile.setGender(request.getGender());
        userProfile.setAge(request.getAge());
        userProfile.setHeight(request.getHeight());
        userProfile.setWeight(request.getWeight());

        // 將健康狀況列表轉換為 JSON 字串存儲
        if (request.getHealthConditions() != null && !request.getHealthConditions().isEmpty()) {
            userProfile.setHealthConditions(String.join(",", request.getHealthConditions()));
        }

        userProfile.setDietGoal(request.getDietGoal());
        userProfile.setPetType(request.getPetType());

        return userProfileRepository.save(userProfile);
    }

    // 根據用戶獲取個人資料
    public Optional<UserProfile> getUserProfile(User user) {
        return userProfileRepository.findByUser(user);
    }

    // 根據用戶ID獲取個人資料
    public Optional<UserProfile> getUserProfileById(Long userId) {
        return userProfileRepository.findByUserId(userId);
    }
}
