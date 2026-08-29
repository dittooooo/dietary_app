package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.ProblemFeedback;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface ProblemFeedbackRepository extends JpaRepository<ProblemFeedback, Long> {
    List<ProblemFeedback> findByUserIdOrderByCreatedAtDesc(Long userId);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("DELETE FROM ProblemFeedback p WHERE p.user.id = :userId")
    void deleteByUserId(@Param("userId") Long userId);

    List<ProblemFeedback> findAllByOrderByCreatedAtDesc();
}
