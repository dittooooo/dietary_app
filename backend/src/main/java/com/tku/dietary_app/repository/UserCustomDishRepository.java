package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.UserCustomDish;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface UserCustomDishRepository extends JpaRepository<UserCustomDish, Long> {
    Optional<UserCustomDish> findByUserIdAndDishNameIgnoreCase(Long userId, String dishName);

    List<UserCustomDish> findByUserIdOrderByUpdatedAtDescIdDesc(Long userId);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("DELETE FROM UserCustomDish d WHERE d.user.id = :userId")
    void deleteByUserId(@Param("userId") Long userId);
}
