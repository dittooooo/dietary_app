package com.tku.dietary_app.entity;

import jakarta.persistence.*;//匯入 JPA 註解。JPA 是用來讓 Java 物件對應資料庫
import lombok.*;
import java.time.LocalDateTime;
import org.hibernate.annotations.CreationTimestamp;//自動記錄資料建立時間

// 用戶實體類別，代表資料庫中的用戶表
@Entity
@Table(name = "users")
@Getter
@Setter
@NoArgsConstructor//自動產生：public User() {}
@AllArgsConstructor//包含所有欄位的 constructor
@Builder
public class User {

    @Id//主鍵
    @GeneratedValue(strategy = GenerationType.IDENTITY)//設定 id 自動生成。
    private Long id;

    @Column(unique = true, nullable = false)
    private String email;

    @Column(nullable = false)
    private String password;

    @Column(nullable = false)
    private String role;

    @Column(nullable = false)
    private Boolean hasCompletedOnboarding = false;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;
}