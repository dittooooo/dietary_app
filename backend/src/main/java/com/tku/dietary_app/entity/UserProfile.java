package com.tku.dietary_app.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.NoArgsConstructor;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDate;
import java.time.LocalDateTime;

// 用戶個人資料實體類別，代表資料庫中的用戶個人資料表
@Entity
@Table(name = "user_profile")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserProfile {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @OneToOne(fetch = FetchType.LAZY)//一個 User 對應一個 UserProfile，LAZY 表示：只有在需要時才讀取 User 資料
    @JoinColumn(name = "user_id", nullable = false, unique = true)//建立資料庫關聯欄位
    private User user;

    @Column(nullable = false)
    private String nickname;

    @Column(nullable = false)
    private String gender;

    @Column(nullable = false)
    private Integer age;

    @Column(nullable = false)
    private Double height;

    @Column(nullable = false)
    private Double weight;

    @Column(columnDefinition = "TEXT", nullable = false)
    private String healthConditions;

    @Column(nullable = false)
    private String dietGoal;

    @Column(nullable = false)
    private String petType;

    private String avatarUrl;

    @Column(name = "bmr")
    private Double bmr;

    @Column(name = "tdee")
    private Double tdee;

    @Column(name = "recommended_calories")
    private Double recommendedCalories;

    @Builder.Default
    @Column(name = "body_score", nullable = false, columnDefinition = "integer default 50")
    private Integer bodyScore = 50;

    @Builder.Default
    @Column(name = "muscle_score", nullable = false, columnDefinition = "integer default 50")
    private Integer muscleScore = 50;

    @Builder.Default
    @Column(name = "body_type", nullable = false, columnDefinition = "varchar(255) default 'NORMAL'")
    private String bodyType = "NORMAL";

    @Column(name = "last_settle_date")
    private LocalDate lastSettleDate;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    void applyBodyStatusDefaults() {
        if (bodyScore == null) {
            bodyScore = 50;
        }
        if (muscleScore == null) {
            muscleScore = 50;
        }
        if (bodyType == null || bodyType.isBlank() || "STANDARD".equalsIgnoreCase(bodyType)) {
            bodyType = "NORMAL";
        }
    }
}
