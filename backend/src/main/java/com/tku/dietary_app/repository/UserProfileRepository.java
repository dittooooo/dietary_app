package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.entity.User;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

// 用戶個人資料倉庫介面，提供資料庫操作
@Repository
public interface UserProfileRepository extends JpaRepository<UserProfile, Long> {
    // 根據用戶查詢個人資料
    Optional<UserProfile> findByUser(User user);
    // 根據用戶ID查詢個人資料
    Optional<UserProfile> findByUserId(Long userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            select profile
            from UserProfile profile
            where profile.user.id = :userId
            """)
    Optional<UserProfile> findByUserIdForUpdate(@Param("userId") Long userId);

    @Query("""
            select profile
            from UserProfile profile
            join profile.user user
            where lower(profile.nickname) like lower(concat('%', :keyword, '%'))
               or lower(user.email) like lower(concat('%', :keyword, '%'))
            """)
    List<UserProfile> searchUsers(@Param("keyword") String keyword);
}
