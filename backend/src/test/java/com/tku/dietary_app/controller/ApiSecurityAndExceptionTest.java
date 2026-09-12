package com.tku.dietary_app.controller;

import com.tku.dietary_app.config.JwtAuthenticationFilter;
import com.tku.dietary_app.config.SecurityConfig;
import com.tku.dietary_app.entity.DietRecord;
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
import com.tku.dietary_app.service.ProblemFeedbackService;
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

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
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
    private ProblemFeedbackService problemFeedbackService;

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
        mockMvc.perform(get("/api/admin/problem-feedback")
                        .with(authentication(authToken("user@example.com", "ROLE_USER"))))
                .andExpect(status().isForbidden());
    }

    @Test
    void adminRouteAllowsAdminUser() throws Exception {
        when(problemFeedbackService.getAll()).thenReturn(List.of());

        mockMvc.perform(get("/api/admin/problem-feedback")
                        .with(authentication(authToken("admin@example.com", "ROLE_ADMIN"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data").isArray());
    }

    @Test
    void dietRecordListAcceptsDateQueryParam() throws Exception {
        User loginUser = User.builder().id(1L).email("user@example.com").password("encoded").build();
        LocalDate recordDate = LocalDate.of(2026, 8, 18);
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(loginUser));
        when(dietRecordService.getRecordsByUserAndDate(1L, recordDate)).thenReturn(List.of(
                DietRecord.builder()
                        .id(12L)
                        .user(loginUser)
                        .dishName("雞胸肉")
                        .date(recordDate)
                        .mealDate(recordDate)
                        .mealType("LUNCH")
                        .amount(1)
                        .build()
        ));

        mockMvc.perform(get("/api/diet-records")
                        .queryParam("date", "2026-08-18")
                        .with(authentication(authToken("user@example.com", "ROLE_USER"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data[0].dishName").value("雞胸肉"))
                .andExpect(jsonPath("$.data[0].date").value("2026-08-18"));

        verify(dietRecordService).getRecordsByUserAndDate(1L, recordDate);
    }

    @Test
    void adminDietRecordRejectsInvalidMealType() throws Exception {
        User loginUser = User.builder().id(1L).email("admin@example.com").password("encoded").build();
        when(userRepository.findByEmail("admin@example.com")).thenReturn(Optional.of(loginUser));

        mockMvc.perform(post("/api/diet-records")
                        .with(authentication(authToken("admin@example.com", "ROLE_ADMIN")))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "dishName": "Chicken Box",
                                  "mealType": "INVALID_MEAL_TYPE",
                                  "calories": 500
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.message").value("mealType 只支援 breakfast、lunch、dinner、other 或 早餐、午餐、晚餐、其他"));
    }

    @Test
    void dietRecordCreateRejectsInvalidDateFormat() throws Exception {
        User loginUser = User.builder().id(1L).email("user@example.com").password("encoded").build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(loginUser));

        mockMvc.perform(post("/api/diet-records")
                        .with(authentication(authToken("user@example.com", "ROLE_USER")))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "dish_name": "雞胸肉",
                                  "meal_type": "LUNCH",
                                  "record_date": "not-a-date"
                                }
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.message").value("日期格式不正確 (not-a-date)，請使用 YYYY-MM-DD 格式"));
    }

    @Test
    void dietRecordCreateAcceptsDishInfoListPayload() throws Exception {
        User loginUser = User.builder().id(1L).email("user@example.com").password("encoded").build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(loginUser));
        when(dietRecordService.create(eq(1L), any())).thenAnswer(invocation -> {
            var request = invocation.getArgument(1, com.tku.dietary_app.dto.DietRecordRequest.class);
            return DietRecord.builder()
                    .id(10L)
                    .user(loginUser)
                    .dishName(request.getDishName())
                    .date(request.getDate())
                    .description(request.getDescription())
                    .mealType(request.getMealType())
                    .amount(request.getAmount() == null ? 1 : request.getAmount())
                    .build();
        });

        mockMvc.perform(post("/api/diet-records")
                        .with(authentication(authToken("user@example.com", "ROLE_USER")))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "dish_info_list": [
                                    {
                                      "dish_name": "雞胸肉",
                                      "amount": 1,
                                      "meal_type": "LUNCH",
                                      "record_date": "2026-08-18",
                                      "description": "午餐"
                                    },
                                    {
                                      "dish_name": "白飯",
                                      "amount": 2,
                                      "meal_type": "LUNCH",
                                      "record_date": "2026-08-18",
                                      "description": "主食"
                                    }
                                  ]
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data[0].dishName").value("雞胸肉"))
                .andExpect(jsonPath("$.data[1].dishName").value("白飯"));
    }

    @Test
    void dietRecordCreateKeepsCommaInsideParenthesesInOneDishName() throws Exception {
        User loginUser = User.builder().id(1L).email("user@example.com").password("encoded").build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(loginUser));
        when(dietRecordService.create(eq(1L), any())).thenAnswer(invocation -> {
            var request = invocation.getArgument(1, com.tku.dietary_app.dto.DietRecordRequest.class);
            return DietRecord.builder()
                    .id(70L)
                    .user(loginUser)
                    .dishName(request.getDishName())
                    .date(request.getDate())
                    .mealType(request.getMealType())
                    .amount(request.getAmount() == null ? 1 : request.getAmount())
                    .build();
        });

        mockMvc.perform(post("/api/diet-records")
                        .with(authentication(authToken("user@example.com", "ROLE_USER")))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "dishName": "珍珠奶茶(去冰,全糖)",
                                  "mealType": "LUNCH",
                                  "calories": 94.02,
                                  "protein": 0.24,
                                  "fat": 2.39,
                                  "carbohydrates": 17.89
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.dishName").value("珍珠奶茶(去冰,全糖)"));
    }

    @Test
    void dietRecordCreateKeepsTopLevelCommaInOneDishName() throws Exception {
        User loginUser = User.builder().id(1L).email("user@example.com").password("encoded").build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(loginUser));
        when(dietRecordService.create(eq(1L), any())).thenAnswer(invocation -> {
            var request = invocation.getArgument(1, com.tku.dietary_app.dto.DietRecordRequest.class);
            return DietRecord.builder()
                    .id(71L)
                    .user(loginUser)
                    .dishName(request.getDishName())
                    .date(request.getDate())
                    .mealType(request.getMealType())
                    .amount(request.getAmount() == null ? 1 : request.getAmount())
                    .build();
        });

        mockMvc.perform(post("/api/diet-records")
                        .with(authentication(authToken("user@example.com", "ROLE_USER")))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "dishName": "冷凍,水晶餃",
                                  "mealType": "LUNCH",
                                  "calories": 190.19,
                                  "protein": 2.83,
                                  "fat": 3.51,
                                  "carbohydrates": 36.83
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.dishName").value("冷凍,水晶餃"));
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
                                  "dish_name": "牛肉麵",
                                  "meal_type": "DINNER",
                                  "description": "updated"
                                }
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.message").value("沒有權限修改這筆紀錄"));
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
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.message").value("僅支援 JPEG、PNG、WEBP 圖片"));
    }

    @Test
    void dietaryAgentUpstreamFailureMapsTo502() throws Exception {
        User loginUser = User.builder().id(1L).email("user@example.com").password("encoded").build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(loginUser));
        when(dietaryAgentService.dishNutrition(any(), any())).thenThrow(new UpstreamServiceException("dietary partner API 呼叫失敗"));

        mockMvc.perform(post("/dietary-agent/dish-nutrition")
                        .with(authentication(authToken("user@example.com", "ROLE_USER")))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "dish_name": "Chicken Box"
                                }
                                """))
                .andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.message").value("dietary partner API 呼叫失敗"));
    }

    @Test
    void dietaryAgentAskAcceptsDishInfoListAndNestedRecords() throws Exception {
        User loginUser = User.builder().id(1L).email("user@example.com").password("encoded").build();
        when(userRepository.findByEmail("user@example.com")).thenReturn(Optional.of(loginUser));
        when(dietaryAgentService.ask(eq(1L), any(), any())).thenReturn(Map.of("answer", "ok"));

        mockMvc.perform(post("/dietary-agent/ask")
                        .with(authentication(authToken("user@example.com", "ROLE_USER")))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "question": "這餐可以嗎？",
                                  "question_type": "single_dish",
                                  "dish_info_list": [
                                    {"dish_name": "雞胸肉", "amount": 1},
                                    {"dish_name": "白飯", "amount": 2}
                                  ],
                                  "user_profile": {
                                    "height_cm": 170,
                                    "weight_kg": 65,
                                    "gender": "MALE",
                                    "age": 25,
                                    "diet_goal": "maintain"
                                  },
                                  "health_condition": {
                                    "has_chronic_disease": false,
                                    "chronic_diseases": []
                                  },
                                  "weekly_diet_records": [
                                    {
                                      "date": "2026-08-18",
                                      "record": [
                                        {
                                          "dish_name": "雞胸肉",
                                          "meal_type": "LUNCH",
                                          "nutrition": {
                                            "calories": 350.0,
                                            "protein": 30.0,
                                            "fat": 8.0,
                                            "carbohydrates": 25.0
                                          },
                                          "amount": 1,
                                          "note": "低油"
                                        }
                                      ]
                                    }
                                  ]
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.answer").value("ok"));
    }

    private UsernamePasswordAuthenticationToken authToken(String email, String authority) {
        return new UsernamePasswordAuthenticationToken(
                email,
                null,
                List.of(new SimpleGrantedAuthority(authority))
        );
    }
}
