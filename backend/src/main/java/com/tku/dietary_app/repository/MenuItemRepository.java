package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.MenuItem;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface MenuItemRepository extends JpaRepository<MenuItem, Long> {
    List<MenuItem> findByDishNameContainingIgnoreCase(String dishName);
}
