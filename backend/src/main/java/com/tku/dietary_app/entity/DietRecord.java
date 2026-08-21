package com.tku.dietary_app.entity;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "diet_records")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DietRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(nullable = false)
    private String dishName;

    @Column(name = "calories")
    private Double calories;

    @Column(name = "protein")
    private Double protein;

    @Column(name = "fat")
    private Double fat;

    @Column(name = "carbohydrates")
    private Double carbohydrates;

    @Column(name = "record_date")
    private LocalDate date;

    @Column(name = "meal_date", nullable = false)
    private LocalDate mealDate;

    @Column(nullable = true)
    private String description;

    @Column(name = "photo_url", nullable = true)
    private String photoUrl;

    @Column(name = "meal_type", nullable = false)
    private String mealType;

    @Column(name = "amount", nullable = false)
    private Integer amount;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false, nullable = false)
    private LocalDateTime createdAt;

    @PrePersist
    private void onCreate() {
        if (date == null) {
            date = LocalDate.now();
        }
        if (mealDate == null) {
            mealDate = date;
        }
        if (amount == null) {
            amount = 1;
        }
    }

    @PreUpdate
    private void onUpdate() {
        if (date == null && mealDate != null) {
            date = mealDate;
        }
        if (mealDate == null && date != null) {
            mealDate = date;
        }
    }
}
