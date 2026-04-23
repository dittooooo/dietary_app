package com.tku.dietary_app.dto;

import lombok.Data;

@Data
public class RestaurantRequest {
    private String name;
    private String address;
    private String phone;
    private String menu;
    private String review;
    private Integer stars;
    private Double latitude;
    private Double longitude;
    private String healthLevel;
}
