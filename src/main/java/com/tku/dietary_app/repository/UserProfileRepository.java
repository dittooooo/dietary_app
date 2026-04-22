package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query; // 必須匯入這個
import org.springframework.data.repository.query.Param; // 必須匯入這個
import org.springframework.stereotype.Repository;

import java.util.List; // 必須匯入這個
import java.util.Optional;

// 用戶個人資料倉庫介面，提供資料庫操作
@Repository
public interface UserProfileRepository extends JpaRepository<UserProfile, Long> {
    // 根據用戶查詢個人資料
    Optional<UserProfile> findByUser(User user);

    // 根據用戶ID查詢個人資料
    Optional<UserProfile> findByUserId(Long userId);

    // 支援同時搜尋「名稱」或「帳號(Email)」，且不分大小寫
    @Query("SELECT p FROM UserProfile p JOIN p.user u WHERE " +
            "LOWER(p.nickname) LIKE LOWER(CONCAT('%', :keyword, '%')) OR " +
            "LOWER(u.email) LIKE LOWER(CONCAT('%', :keyword, '%'))")
    List<UserProfile> searchUsers(@Param("keyword") String keyword);
}

