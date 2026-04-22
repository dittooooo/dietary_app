package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.User;//匯入 User 類別。是一個 Entity，代表資料庫的一張表
import org.springframework.data.jpa.repository.JpaRepository;//匯入 Spring Data JPA 的 JpaRepository。這個介面非常重要，它提供很多現成的資料庫操作方法，例如：讓你不用自己寫 SQL

import java.util.Optional;//匯入 Optional 類別，這個資料「可能存在，也可能不存在」，找得到使用者 → 回傳 User，找不到 → 回傳 empty

// 用戶倉庫介面，提供用戶資料庫操作，JpaRepository<資料表對應的Entity, 主鍵型別>
public interface UserRepository extends JpaRepository<User, Long> {
    // 根據電子郵件查詢用戶
    // 建立一個方法，用 email 查找使用者，Spring 就會自動幫你產生 SQL
    Optional<User> findByEmail(String email);
}
