package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

// 用戶個人資料倉庫介面，提供資料庫操作
@Repository
public interface UserProfileRepository extends JpaRepository<UserProfile, Long> {
    // 根據用戶查詢個人資料
    Optional<UserProfile> findByUser(User user);
    // 根據用戶ID查詢個人資料
    Optional<UserProfile> findByUserId(Long userId);
}
