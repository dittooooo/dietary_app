package com.tku.dietary_app.repository;

import com.tku.dietary_app.entity.ProblemFeedback;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ProblemFeedbackRepository extends JpaRepository<ProblemFeedback, Long> {
    List<ProblemFeedback> findByUserIdOrderByCreatedAtDesc(Long userId);
}
