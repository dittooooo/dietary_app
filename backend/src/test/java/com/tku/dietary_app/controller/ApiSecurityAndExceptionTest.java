package com.tku.dietary_app.controller;

import com.tku.dietary_app.config.JwtAuthenticationFilter;
import com.tku.dietary_app.config.SecurityConfig;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.entity.UserProfile;
import com.tku.dietary_app.exception.FileValidationException;
import com.tku.dietary_app.exception.ForbiddenOperationException;
import com.tku.dietary_app.exception.GlobalExceptionHandler;
import com.tku.dietary_app.exception.UpstreamServiceException;
import com.tku.dietary_app.repository.UserProfileRepository;
import com.tku.dietary_app.repository.UserRepository;
import com.tku.dietary_app.service.AdminService;
import com.tku.dietary_app.service.DietRecordService;
import com.tku.dietary_app.service.DietaryAgentService;
import com.tku.dietary_app.service.ImageStorageService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest({
        AdminController.class,
        DietRecordController.class,
        DietaryAgentController.class,
        AvatarController.class
})
@Import({SecurityConfig.class, GlobalExceptionHandler.class})
class ApiSecurityAndExceptionTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private AdminService adminService;

    @MockitoBean
    private DietRecordService dietRecordService;

    @MockitoBean
    private DietaryAgentService dietaryAgentService;

    @MockitoBean
    private UserRepository userRepository;

    @MockitoBean
    private UserProfileRepository userProfileRepository;

    @MockitoBean
    private ImageStorageService imageStorageService;

    @MockitoBean
    private JwtAuthenticationFilter jwtAuthenticationFilter;

    @BeforeEach
    void setUpFilter() throws Exception {
        doAnswer(invocation -> {
            jakarta.servlet.FilterChain chain = invocation.getArgument(2);
            jakarta.servlet.ServletRequest request = invocation.getArgument(0);
            jakarta.servlet.ServletResponse response = invocation.getArgument(1);
            chain.doFilter(request, response);
            return null;
        }).when(jwtAuthenticationFilter).doFilter(any(), any(), any());
    }

    @Test
    void adminRouteRejectsNormalUser() throws Exception {
        mockMvc.perform(get("/api/admin/users")
                        .with(authentication(authToken("user@example.com", "ROLE_USER"))))
                .andExpect(status().isForbidden());
    }

    @Test
    void adminRouteAllowsAdminUser() throws Exception {
        when(adminService.getAllUsers()).thenReturn(List.of());

        mockMvc.perform(get("/api/admin/users")
                        .with(authentication(authToken("admin@example.com", "ROLE_ADMIN"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data").isArray());
    }

    @Test
    void adminDietRecordRejectsInvalidMealType() throws Exception {
        mockMvc.perform(post("/api/admin/diet-records")
                        .with(authentication(authToken("admin@example.com", "ROLE_ADMIN")))
                        .param("userId", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "dishName": "Chicken Box",
                                  "mealType": "SNACK",
                                  "calories": 500
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.mealType").exists());
    }

    @Test
    void dietRecordForbiddenOperationMapsTo403() throws Exception {
        User loginUser = User.builder().id(1L).email("user@example.com").password("encoded").build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(loginUser));
        when(dietRecordService.update(eq(5L), eq(1L), any())).thenThrow(new ForbiddenOperationException("沒有權限修改這筆紀錄"));

        mockMvc.perform(put("/api/diet-records/5")
                        .with(authentication(authToken("user@example.com", "ROLE_USER")))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "description": "updated"
                                }
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("沒有權限修改這筆紀錄"));
    }

    @Test
    void avatarUploadInvalidFileMapsTo400() throws Exception {
        User loginUser = User.builder().id(8L).email("user@example.com").password("encoded").build();
        UserProfile profile = UserProfile.builder().id(10L).user(loginUser).nickname("tester").gender("female").age(20).height(160.0).weight(50.0).healthConditions("none").dietGoal("maintain").petType("cat").build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(loginUser));
        when(userProfileRepository.findByUserId(8L)).thenReturn(Optional.of(profile));
        doThrow(new FileValidationException("僅支援 JPEG、PNG、WEBP 圖片"))
                .when(imageStorageService).storeImage(any(MultipartFile.class), any(), any());

        mockMvc.perform(multipart("/api/user/avatar")
                        .file("file", "not-an-image".getBytes())
                        .with(authentication(authToken("user@example.com", "ROLE_USER"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("僅支援 JPEG、PNG、WEBP 圖片"));
    }

    @Test
    void dietaryAgentUpstreamFailureMapsTo502() throws Exception {
        User loginUser = User.builder().id(1L).email("user@example.com").password("encoded").build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(loginUser));
        when(dietaryAgentService.dishNutrition(any())).thenThrow(new UpstreamServiceException("dietary partner API 呼叫失敗"));

        mockMvc.perform(post("/dietary-agent/dish-nutrition")
                        .with(authentication(authToken("user@example.com", "ROLE_USER")))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "dish_name": "Chicken Box"
                                }
                                """))
                .andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.error").value("dietary partner API 呼叫失敗"));
    }

    private UsernamePasswordAuthenticationToken authToken(String email, String authority) {
        return new UsernamePasswordAuthenticationToken(
                email,
                null,
                List.of(new SimpleGrantedAuthority(authority))
        );
    }
}
