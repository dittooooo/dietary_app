package com.tku.dietary_app.entity;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;

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

    @Column(columnDefinition = "TEXT", nullable = false)
    private String nutrition;

    @Column(nullable = true)
    private String description;

    @Column(name = "photo_url", nullable = true)
    private String photoUrl;

    @Column(name = "meal_type", nullable = false)
    private String mealType;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false, nullable = false)
    private LocalDateTime createdAt;
}
