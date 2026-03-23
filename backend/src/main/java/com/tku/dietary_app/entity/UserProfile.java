package com.tku.dietary_app.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

// 用戶個人資料實體類別，代表資料庫中的用戶個人資料表
@Entity
@Table(name = "user_profile")
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

    @Column(columnDefinition = "TEXT")
    private String healthConditions;

    @Column(nullable = false)
    private String dietGoal;

    @Column(nullable = false)
    private String petType;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    // Constructors
    public UserProfile() {}

    public UserProfile(User user, String nickname, String gender, Integer age, Double height,
                      Double weight, String healthConditions, String dietGoal, String petType) {
        this.user = user;
        this.nickname = nickname;
        this.gender = gender;
        this.age = age;
        this.height = height;
        this.weight = weight;
        this.healthConditions = healthConditions;
        this.dietGoal = dietGoal;
        this.petType = petType;
    }

    @PrePersist
    protected void onCreate() {
        createdAt = LocalDateTime.now();
        updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

    // Getters and Setters
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public User getUser() { return user; }
    public void setUser(User user) { this.user = user; }

    public String getNickname() { return nickname; }
    public void setNickname(String nickname) { this.nickname = nickname; }

    public String getGender() { return gender; }
    public void setGender(String gender) { this.gender = gender; }

    public Integer getAge() { return age; }
    public void setAge(Integer age) { this.age = age; }

    public Double getHeight() { return height; }
    public void setHeight(Double height) { this.height = height; }

    public Double getWeight() { return weight; }
    public void setWeight(Double weight) { this.weight = weight; }

    public String getHealthConditions() { return healthConditions; }
    public void setHealthConditions(String healthConditions) { this.healthConditions = healthConditions; }

    public String getDietGoal() { return dietGoal; }
    public void setDietGoal(String dietGoal) { this.dietGoal = dietGoal; }

    public String getPetType() { return petType; }
    public void setPetType(String petType) { this.petType = petType; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public LocalDateTime getUpdatedAt() { return updatedAt; }
}
