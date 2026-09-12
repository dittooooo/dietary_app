package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.ApiResponse;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.exception.ResourceNotFoundException;
import com.tku.dietary_app.exception.UnauthorizedException;
import com.tku.dietary_app.repository.UserProfileRepository;
import com.tku.dietary_app.repository.UserRepository;
import com.tku.dietary_app.service.ImageStorageService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;

@RestController
@RequiredArgsConstructor
public class AvatarController {

    private final UserRepository userRepository;
    private final UserProfileRepository userProfileRepository;
    private final ImageStorageService imageStorageService;

    @Value("${app.upload.dir}")
    private String uploadDir;

    @PostMapping("/api/user/avatar")
    public ResponseEntity<ApiResponse<String>> uploadMyAvatar(@RequestParam("file") MultipartFile file) {
        User user = getAuthenticatedUser();
        if (user == null) {
            throw new UnauthorizedException("未登入");
        }
        return saveAvatar(file, user.getId());
    }

    private ResponseEntity<ApiResponse<String>> saveAvatar(MultipartFile file, UserProfile profile) {
        Long userId = profile.getUser().getId();

        try {
            Path dir = Paths.get(uploadDir, "avatars");
            String filename = imageStorageService.storeImage(file, dir, "user_" + userId);
            profile.setAvatarUrl("/avatars/" + filename);
            userProfileRepository.save(profile);
            return ResponseEntity.ok(ApiResponse.success("頭像上傳成功", profile.getAvatarUrl()));
        } catch (IOException e) {
            throw new IllegalStateException("頭像儲存失敗", e);
        }
    }

    private ResponseEntity<ApiResponse<String>> saveAvatar(MultipartFile file, Long userId) {
        UserProfile profile = userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new ResourceNotFoundException("找不到使用者個人資料 (userId: " + userId + ")"));

        return saveAvatar(file, profile);
    }

    private User getAuthenticatedUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated()) {
            return null;
        }
        return userRepository.findByEmail(auth.getPrincipal().toString()).orElse(null);
    }
}
