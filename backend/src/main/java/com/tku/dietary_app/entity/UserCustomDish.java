package com.tku.dietary_app.entity;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(
        name = "user_custom_dishes",
        uniqueConstraints = {
                @UniqueConstraint(name = "uk_user_custom_dishes_user_name", columnNames = {"user_id", "dish_name"})
        }
)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserCustomDish {

    public static final String TYPE_MANUAL = "MANUAL";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(name = "dish_name", nullable = false, length = 255)
    private String dishName;

    @Column(nullable = false)
    private Double calories;

    @Column(nullable = false)
    private Double protein;

    @Column(nullable = false)
    private Double fat;

    @Column(name = "carbohydrates", nullable = false)
    private Double carbohydrates;

    @Column(name = "type", nullable = false, length = 50)
    private String type;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false, nullable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;
}
