package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.MenuItemRequest;
import com.tku.dietary_app.entity.MenuItem;
import com.tku.dietary_app.repository.MenuItemRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
public class MenuItemService {

    private final MenuItemRepository menuItemRepository;

    public List<MenuItem> getAllMenuItems() {
        return menuItemRepository.findAll();
    }

    public List<MenuItem> searchByDishName(String dishName) {
        return menuItemRepository.findByDishNameContainingIgnoreCase(dishName);
    }

    public MenuItem create(MenuItemRequest request) {
        return menuItemRepository.save(MenuItem.builder()
                .restaurantName(request.getRestaurantName())
                .dishName(request.getDishName())
                .ingredients(request.getIngredients())
                .nutrition(request.getNutrition())
                .recommendLevel(request.getRecommendLevel())
                .build());
    }

    public MenuItem update(Long id, MenuItemRequest request) {
        MenuItem item = menuItemRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("找不到菜單 (ID: " + id + ")"));
        item.setRestaurantName(request.getRestaurantName());
        item.setDishName(request.getDishName());
        item.setIngredients(request.getIngredients());
        item.setNutrition(request.getNutrition());
        item.setRecommendLevel(request.getRecommendLevel());
        return menuItemRepository.save(item);
    }

    public void delete(Long id) {
        if (!menuItemRepository.existsById(id)) {
            throw new RuntimeException("找不到菜單 (ID: " + id + ")");
        }
        menuItemRepository.deleteById(id);
    }
}
