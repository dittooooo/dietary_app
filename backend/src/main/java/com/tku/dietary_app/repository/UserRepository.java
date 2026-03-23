package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

// 用戶倉庫介面，提供用戶資料庫操作
public interface UserRepository extends JpaRepository<User, Long> {
    // 根據電子郵件查詢用戶
    Optional<User> findByEmail(String email);
}
