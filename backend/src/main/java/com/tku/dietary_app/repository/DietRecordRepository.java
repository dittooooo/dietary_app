package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.DietRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;

@Repository
public interface DietRecordRepository extends JpaRepository<DietRecord, Long> {
    List<DietRecord> findByDishNameContainingIgnoreCase(String dishName);

    List<DietRecord> findByUserIdOrderByMealDateDescCreatedAtDescIdDesc(Long userId);

    @Query("""
            SELECT COUNT(d) AS recordCount,
                   COALESCE(SUM(d.calories), 0) AS totalCalories,
                   COALESCE(SUM(d.protein), 0) AS totalProtein
            FROM DietRecord d
            WHERE d.user.id = :userId
              AND d.mealDate = :mealDate
            """)
    DailyNutritionSummary summarizeByUserAndMealDate(@Param("userId") Long userId,
                                                     @Param("mealDate") LocalDate mealDate);

    @Query("""
            SELECT d
            FROM DietRecord d
            LEFT JOIN UserProfile up ON up.user.id = d.user.id
            WHERE (:userId IS NULL OR d.user.id = :userId)
              AND (:nickname IS NULL OR LOWER(up.nickname) LIKE LOWER(CONCAT('%', :nickname, '%')))
              AND (:dishName IS NULL OR LOWER(d.dishName) LIKE LOWER(CONCAT('%', :dishName, '%')))
              AND (:mealType IS NULL OR d.mealType = :mealType)
              AND (:startDate IS NULL OR d.mealDate >= :startDate)
              AND (:endDate IS NULL OR d.mealDate < :endDate)
            ORDER BY d.mealDate DESC, d.createdAt DESC, d.id DESC
            """)
    List<DietRecord> findByAdminFilters(@Param("userId") Long userId,
                                        @Param("nickname") String nickname,
                                        @Param("dishName") String dishName,
                                        @Param("mealType") String mealType,
                                        @Param("startDate") LocalDate startDate,
                                        @Param("endDate") LocalDate endDate);

    interface DailyNutritionSummary {
        Long getRecordCount();

        Double getTotalCalories();

        Double getTotalProtein();
    }
}
