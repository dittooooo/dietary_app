package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.RestaurantRequest;
import com.tku.dietary_app.entity.Restaurant;
import com.tku.dietary_app.repository.RestaurantRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
public class RestaurantService {

    private final RestaurantRepository restaurantRepository;

    public List<Restaurant> getAllRestaurants() {
        return restaurantRepository.findAll();
    }

    public List<Restaurant> searchByName(String name) {
        return restaurantRepository.findByNameContainingIgnoreCase(name);
    }

    public Restaurant getById(Long id) {
        return restaurantRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到餐廳 (ID: " + id + ")"));
    }

    public Restaurant create(RestaurantRequest request) {
        Restaurant restaurant = Restaurant.builder()
                .name(request.getName())
                .address(request.getAddress())
                .phone(request.getPhone())
                .review(request.getReview())
                .stars(request.getStars())
                .latitude(request.getLatitude())
                .longitude(request.getLongitude())
                .build();
        return restaurantRepository.save(restaurant);
    }

    public Restaurant update(Long id, RestaurantRequest request) {
        Restaurant restaurant = restaurantRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到餐廳 (ID: " + id + ")"));
        restaurant.setName(request.getName());
        restaurant.setAddress(request.getAddress());
        restaurant.setPhone(request.getPhone());
        restaurant.setReview(request.getReview());
        restaurant.setStars(request.getStars());
        restaurant.setLatitude(request.getLatitude());
        restaurant.setLongitude(request.getLongitude());
        return restaurantRepository.save(restaurant);
    }

    public void delete(Long id) {
        if (!restaurantRepository.existsById(id)) {
            throw new RuntimeException("找不到餐廳 (ID: " + id + ")");
        }
        restaurantRepository.deleteById(id);
    }
}
