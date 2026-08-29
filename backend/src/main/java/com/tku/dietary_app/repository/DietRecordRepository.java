package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.DietRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface DietRecordRepository extends JpaRepository<DietRecord, Long> {
    interface DailyNutritionSummary {
        Long getRecordCount();
        Double getTotalCalories();
        Double getTotalProtein();
    }

    List<DietRecord> findByDishNameContainingIgnoreCase(String dishName);

    List<DietRecord> findByUserIdOrderByDateDescCreatedAtDescIdDesc(Long userId);

    @org.springframework.data.jpa.repository.Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("DELETE FROM DietRecord d WHERE d.user.id = :userId")
    void deleteByUserId(@Param("userId") Long userId);

    List<DietRecord> findByUserIdAndCreatedAtGreaterThanEqualOrderByCreatedAtDescIdDesc(Long userId, LocalDateTime createdAt);

    @Query("""
            SELECT COUNT(d) AS recordCount,
                   COALESCE(SUM(d.calories), 0) AS totalCalories,
                   COALESCE(SUM(d.protein), 0) AS totalProtein
            FROM DietRecord d
            WHERE d.user.id = :userId
              AND d.date = :recordDate
            """)
    DailyNutritionSummary summarizeByUserAndRecordDate(@Param("userId") Long userId,
                                                       @Param("recordDate") LocalDate recordDate);

    @Query("""
            SELECT d
            FROM DietRecord d
            LEFT JOIN UserProfile up ON up.user.id = d.user.id
            WHERE (:userId IS NULL OR d.user.id = :userId)
              AND (:nickname IS NULL OR LOWER(up.nickname) LIKE LOWER(CONCAT('%', :nickname, '%')))
              AND (:dishName IS NULL OR LOWER(d.dishName) LIKE LOWER(CONCAT('%', :dishName, '%')))
              AND (:mealType IS NULL OR d.mealType = :mealType)
              AND (:startDate IS NULL OR d.date >= :startDate)
              AND (:endDate IS NULL OR d.date < :endDate)
            ORDER BY d.date DESC, d.createdAt DESC, d.id DESC
            """)
    List<DietRecord> findByAdminFilters(@Param("userId") Long userId,
                                        @Param("nickname") String nickname,
                                        @Param("dishName") String dishName,
                                        @Param("mealType") String mealType,
                                        @Param("startDate") LocalDate startDate,
                                        @Param("endDate") LocalDate endDate);
}
