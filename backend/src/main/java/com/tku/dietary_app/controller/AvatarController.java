package com.tku.dietary_app.controller;

import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.repository.UserProfileRepository;
import com.tku.dietary_app.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.UUID;

@RestController
@RequiredArgsConstructor
public class AvatarController {

    private final UserRepository userRepository;
    private final UserProfileRepository userProfileRepository;

    @Value("${app.upload.dir}")
    private String uploadDir;

    // 一般使用者上傳自己的大頭像
    @PostMapping("/api/user/avatar")
    public ResponseEntity<?> uploadMyAvatar(@RequestParam("file") MultipartFile file) {
        User user = getAuthenticatedUser();
        if (user == null) return ResponseEntity.status(401).body("使用者未認證");
        return saveAvatar(file, user.getId());
    }

    // Admin 幫指定使用者上傳大頭像
    @PostMapping("/api/admin/users/{userId}/avatar")
    public ResponseEntity<?> uploadUserAvatar(@PathVariable Long userId,
                                              @RequestParam("file") MultipartFile file) {
        return saveAvatar(file, userId);
    }

    private ResponseEntity<?> saveAvatar(MultipartFile file, Long userId) {
        UserProfile profile = userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new RuntimeException("找不到使用者 Profile (userId: " + userId + ")"));

        String ext = getExtension(file.getOriginalFilename());
        String filename = "user_" + userId + "_" + UUID.randomUUID() + ext;

        try {
            Path dir = Paths.get(uploadDir);
            Files.createDirectories(dir);
            Files.copy(file.getInputStream(), dir.resolve(filename),
                    java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException e) {
            return ResponseEntity.status(500).body("上傳失敗：" + e.getMessage());
        }

        profile.setAvatarUrl("/avatars/" + filename);
        userProfileRepository.save(profile);

        return ResponseEntity.ok(profile.getAvatarUrl());
    }

    private User getAuthenticatedUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated()) return null;
        return userRepository.findByEmail(auth.getPrincipal().toString()).orElse(null);
    }

    private String getExtension(String filename) {
        if (filename == null || !filename.contains(".")) return ".jpg";
        return filename.substring(filename.lastIndexOf("."));
    }
}
