package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.ProblemFeedbackRequest;
import com.tku.dietary_app.dto.ProblemFeedbackReplyRequest;
import com.tku.dietary_app.entity.ProblemFeedback;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.exception.ResourceNotFoundException;
import com.tku.dietary_app.repository.ProblemFeedbackRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class ProblemFeedbackService {
    private final ProblemFeedbackRepository problemFeedbackRepository;
    private final UserProfileService userProfileService;

    @Transactional
    public ProblemFeedback create(User user, ProblemFeedbackRequest request) {
        String userName = userProfileService.getUserProfile(user)
                .map(profile -> profile.getNickname())
                .filter(nickname -> nickname != null && !nickname.isBlank())
                .orElse(user.getEmail());

        ProblemFeedback feedback = ProblemFeedback.builder()
                .user(user)
                .userName(userName)
                .content(request.getContent().trim())
                .build();

        return problemFeedbackRepository.save(feedback);
    }

    @Transactional(readOnly = true)
    public List<ProblemFeedback> getByUser(User user) {
        return problemFeedbackRepository.findByUserIdOrderByCreatedAtDesc(user.getId());
    }

    @Transactional(readOnly = true)
    public List<ProblemFeedback> getAll() {
        return problemFeedbackRepository.findAllByOrderByCreatedAtDesc();
    }

    @Transactional
    public ProblemFeedback reply(Long id, ProblemFeedbackReplyRequest request) {
        ProblemFeedback feedback = problemFeedbackRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("找不到問題回饋"));

        feedback.setAdminReply(request.getAdminReply().trim());
        feedback.setRepliedAt(LocalDateTime.now());
        return problemFeedbackRepository.save(feedback);
    }
}
