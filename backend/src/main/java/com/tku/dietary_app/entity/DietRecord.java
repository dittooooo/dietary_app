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

    @Column(nullable = false)
    private String dishName;

    @Column(columnDefinition = "TEXT")
    private String nutrition;

    @Column(columnDefinition = "TEXT")
    private String cumulativeNutrition;

    private String healthLevel;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;
}
