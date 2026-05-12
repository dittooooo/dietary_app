package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.DietRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface DietRecordRepository extends JpaRepository<DietRecord, Long> {
    List<DietRecord> findByDishNameContainingIgnoreCase(String dishName);

    List<DietRecord> findByUserIdOrderByCreatedAtDescIdDesc(Long userId);

    @Query("""
            SELECT d
            FROM DietRecord d
            LEFT JOIN UserProfile up ON up.user.id = d.user.id
            WHERE (:userId IS NULL OR d.user.id = :userId)
              AND (:nickname IS NULL OR LOWER(up.nickname) LIKE LOWER(CONCAT('%', :nickname, '%')))
              AND (:dishName IS NULL OR LOWER(d.dishName) LIKE LOWER(CONCAT('%', :dishName, '%')))
              AND (:mealType IS NULL OR d.mealType = :mealType)
              AND (:startAt IS NULL OR d.createdAt >= :startAt)
              AND (:endAt IS NULL OR d.createdAt < :endAt)
            ORDER BY d.createdAt DESC, d.id DESC
            """)
    List<DietRecord> findByAdminFilters(@Param("userId") Long userId,
                                        @Param("nickname") String nickname,
                                        @Param("dishName") String dishName,
                                        @Param("mealType") String mealType,
                                        @Param("startAt") LocalDateTime startAt,
                                        @Param("endAt") LocalDateTime endAt);
}
