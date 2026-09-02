package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.UserCustomDish;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface UserCustomDishRepository extends JpaRepository<UserCustomDish, Long> {
    Optional<UserCustomDish> findByUserIdAndDishNameIgnoreCase(Long userId, String dishName);

    List<UserCustomDish> findByUserIdOrderByUpdatedAtDescIdDesc(Long userId);
}
