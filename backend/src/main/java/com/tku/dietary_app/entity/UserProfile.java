package com.tku.dietary_app.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDate;
import java.time.LocalDateTime;

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

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false, unique = true)
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
