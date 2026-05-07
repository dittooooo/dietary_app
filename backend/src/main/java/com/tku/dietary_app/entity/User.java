package com.tku.dietary_app.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

/**
 * users 資料表。
 *
 * 這張表放登入需要的資料：
 * email、加密後密碼、角色、是否完成 onboarding。
 */
@Entity
@Table(name = "users")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true, nullable = false)
    private String email;

    // 這裡存的是 BCrypt 加密後的密碼，不是明文密碼。
    @Column(nullable = false)
    private String password;

    // Spring Security 使用 ROLE_USER / ROLE_ADMIN 判斷 API 權限。
    @Builder.Default
    private String role = "ROLE_USER";

    // 註冊後尚未填完個人資料時是 false。
    @Builder.Default
    @Column(nullable = false)
    private Boolean hasCompletedOnboarding = false;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;
}
