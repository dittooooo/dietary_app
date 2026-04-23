package com.tku.dietary_app.entity;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "restaurants")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Restaurant {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    @Column(nullable = false)
    private String address;

    private String phone;

    @Column(columnDefinition = "TEXT")
    private String menu;

    @Column(columnDefinition = "TEXT")
    private String review;

    private Integer stars;

    private Double latitude;

    private Double longitude;

    private String healthLevel;
}
