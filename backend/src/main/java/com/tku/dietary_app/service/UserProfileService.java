package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.OnboardingRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.repository.UserProfileRepository;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

@Service
@RequiredArgsConstructor
public class UserProfileService {
    private final UserProfileRepository userProfileRepository;
    private final UserRepository userRepository;
    private final BodyMetricsService bodyMetricsService;

    @Transactional
    public UserProfile createOrUpdateUserProfile(User user, OnboardingRequest request) {
        Optional<UserProfile> existingProfile = userProfileRepository.findByUser(user);

        UserProfile userProfile = existingProfile.orElseGet(() -> {
            UserProfile profile = new UserProfile();
            profile.setUser(user);
            return profile;
        });

        userProfile.setNickname(request.getNickname());
        userProfile.setGender(request.getGender());
        userProfile.setAge(request.getAge());
        userProfile.setHeight(request.getHeight());
        userProfile.setWeight(request.getWeight());
        userProfile.setHealthConditions(String.join(",", request.getHealthConditions()));
        userProfile.setDietGoal(request.getDietGoal());
        userProfile.setPetType(request.getPetType());
        bodyMetricsService.recalculateAndApply(userProfile);
        user.setHasCompletedOnboarding(true);
        userRepository.save(user);

        return userProfileRepository.save(userProfile);
    }

    public Optional<UserProfile> getUserProfile(User user) {
        return userProfileRepository.findByUser(user);
    }

    public Optional<UserProfile> getUserProfileById(Long userId) {
        return userProfileRepository.findByUserId(userId);
    }
}
