package com.tku.dietary_app.controller;

import com.tku.dietary_app.dto.AdminUserRequest;
import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.dto.MenuItemRequest;
import com.tku.dietary_app.dto.RestaurantRequest;
import com.tku.dietary_app.service.AdminService;
import com.tku.dietary_app.service.DietRecordService;
import com.tku.dietary_app.service.MenuItemService;
import com.tku.dietary_app.service.RestaurantService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminController {

    private final AdminService adminService;
    private final RestaurantService restaurantService;
    private final MenuItemService menuItemService;
    private final DietRecordService dietRecordService;

    // 標籤 1：使用者清單 (含搜尋)
    @GetMapping("/users")
    public ResponseEntity<?> listUsers(@RequestParam(required = false) String keyword) {
        if (keyword != null) return ResponseEntity.ok(adminService.searchUsers(keyword));
        return ResponseEntity.ok(adminService.getAllUsers());
    }

    // 單筆查詢
    @GetMapping("/users/{id}")
    public ResponseEntity<?> getUser(@PathVariable Long id) {
        return ResponseEntity.ok(adminService.getUserById(id));
    }

    // 標籤 2：確認新增
    @PostMapping("/users")
    public ResponseEntity<?> addUser(@RequestBody AdminUserRequest request) {
        return ResponseEntity.ok(adminService.createUser(request));
    }

    // 標籤 3：確認編輯
    @PutMapping("/users/{id}")
    public ResponseEntity<?> editUser(@PathVariable Long id, @RequestBody AdminUserRequest request) {
        return ResponseEntity.ok(adminService.updateUser(id, request));
    }

    // 標籤 4：確認刪除
    @DeleteMapping("/users/{id}")
    public ResponseEntity<?> removeUser(@PathVariable Long id) {
        adminService.deleteUser(id);
        return ResponseEntity.ok("刪除成功");
    }

    // ===== 餐廳管理 =====

    @GetMapping("/restaurants")
    public ResponseEntity<?> listRestaurants(@RequestParam(required = false) String name) {
        if (name != null) return ResponseEntity.ok(restaurantService.searchByName(name));
        return ResponseEntity.ok(restaurantService.getAllRestaurants());
    }

    @PostMapping("/restaurants")
    public ResponseEntity<?> addRestaurant(@RequestBody RestaurantRequest request) {
        return ResponseEntity.ok(restaurantService.create(request));
    }

    @PutMapping("/restaurants/{id}")
    public ResponseEntity<?> editRestaurant(@PathVariable Long id, @RequestBody RestaurantRequest request) {
        return ResponseEntity.ok(restaurantService.update(id, request));
    }

    @DeleteMapping("/restaurants/{id}")
    public ResponseEntity<?> removeRestaurant(@PathVariable Long id) {
        restaurantService.delete(id);
        return ResponseEntity.ok("刪除成功");
    }

    // ===== 菜單管理 =====

    @GetMapping("/menus")
    public ResponseEntity<?> listMenuItems(@RequestParam(required = false) String dishName) {
        if (dishName != null) return ResponseEntity.ok(menuItemService.searchByDishName(dishName));
        return ResponseEntity.ok(menuItemService.getAllMenuItems());
    }

    @PostMapping("/menus")
    public ResponseEntity<?> addMenuItem(@RequestBody MenuItemRequest request) {
        return ResponseEntity.ok(menuItemService.create(request));
    }

    @PutMapping("/menus/{id}")
    public ResponseEntity<?> editMenuItem(@PathVariable Long id, @RequestBody MenuItemRequest request) {
        return ResponseEntity.ok(menuItemService.update(id, request));
    }

    @DeleteMapping("/menus/{id}")
    public ResponseEntity<?> removeMenuItem(@PathVariable Long id) {
        menuItemService.delete(id);
        return ResponseEntity.ok("刪除成功");
    }

    // ===== 過去飲食管理 =====

    @GetMapping("/diet-records")
    public ResponseEntity<?> listDietRecords(@RequestParam(required = false) String dishName) {
        if (dishName != null) return ResponseEntity.ok(dietRecordService.searchByDishName(dishName));
        return ResponseEntity.ok(dietRecordService.getAllRecords());
    }

    @PostMapping("/diet-records")
    public ResponseEntity<?> addDietRecord(@RequestBody DietRecordRequest request) {
        return ResponseEntity.ok(dietRecordService.create(request));
    }

    @PutMapping("/diet-records/{id}")
    public ResponseEntity<?> editDietRecord(@PathVariable Long id, @RequestBody DietRecordRequest request) {
        return ResponseEntity.ok(dietRecordService.update(id, request));
    }

    @DeleteMapping("/diet-records/{id}")
    public ResponseEntity<?> removeDietRecord(@PathVariable Long id) {
        dietRecordService.delete(id);
        return ResponseEntity.ok("刪除成功");
    }
}