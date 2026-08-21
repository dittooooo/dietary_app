package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.ProblemFeedbackRequest;
import com.tku.dietary_app.entity.ProblemFeedback;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.ProblemFeedbackRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

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
}
