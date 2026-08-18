package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.AdminUserRequest;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.repository.UserProfileRepository;
import com.tku.dietary_app.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.LocalDate;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AdminServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private UserProfileRepository userProfileRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private BodyMetricsService bodyMetricsService;

    @InjectMocks
    private AdminService adminService;

    @Test
    void createUserNormalizesEmailBeforeSaving() {
        AdminUserRequest request = buildRequest();
        request.setEmail("  Admin@Example.COM ");

        when(userRepository.findByEmailIgnoreCase("admin@example.com")).thenReturn(Optional.empty());
        when(passwordEncoder.encode("Password123")).thenReturn("encoded-password");
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> {
            User user = invocation.getArgument(0);
            user.setId(1L);
            return user;
        });
        when(userProfileRepository.save(any(UserProfile.class))).thenAnswer(invocation -> invocation.getArgument(0));

        UserProfile result = adminService.createUser(request);

        assertThat(result.getUser().getEmail()).isEqualTo("admin@example.com");
        verify(userRepository).findByEmailIgnoreCase("admin@example.com");
    }

    @Test
    void createUserRejectsDuplicateEmailIgnoringCase() {
        AdminUserRequest request = buildRequest();
        request.setEmail("Admin@Example.com");

        when(userRepository.findByEmailIgnoreCase("admin@example.com"))
                .thenReturn(Optional.of(User.builder().id(99L).email("admin@example.com").build()));

        assertThatThrownBy(() -> adminService.createUser(request))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Email 已被使用");

        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    void updateUserRejectsDuplicateEmailFromAnotherUser() {
        AdminUserRequest request = buildRequest();
        request.setEmail("Taken@Example.com");

        User currentUser = User.builder().id(1L).email("owner@example.com").build();
        UserProfile profile = UserProfile.builder()
                .id(1L)
                .user(currentUser)
                .nickname("owner")
                .gender("female")
                .age(20)
                .height(160.0)
                .weight(50.0)
                .healthConditions("none")
                .dietGoal("maintain")
                .petType("cat")
                .build();

        when(userProfileRepository.findById(1L)).thenReturn(Optional.of(profile));
        when(userRepository.findByEmailIgnoreCase("taken@example.com"))
                .thenReturn(Optional.of(User.builder().id(2L).email("taken@example.com").build()));

        assertThatThrownBy(() -> adminService.updateUser(1L, request))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Email 已被使用");
    }

    private AdminUserRequest buildRequest() {
        AdminUserRequest request = new AdminUserRequest();
        request.setEmail("user@example.com");
        request.setPassword("Password123");
        request.setRole("ADMIN");
        request.setName("Admin");
        request.setGender("female");
        request.setBirthDate(LocalDate.of(1999, 5, 13));
        request.setHeight(165.0);
        request.setWeight(55.0);
        request.setSpecialDisease("none");
        request.setDietGoal("maintain");
        request.setPetType("cat");
        return request;
    }
}
