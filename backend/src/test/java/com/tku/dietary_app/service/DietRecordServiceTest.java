package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.entity.DietRecord;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.DietRecordRepository;
import com.tku.dietary_app.repository.UserRepository;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class DietRecordServiceTest {
    private final DietRecordRepository dietRecordRepository = mock(DietRecordRepository.class);
    private final UserRepository userRepository = mock(UserRepository.class);
    private final DietaryAgentService dietaryAgentService = mock(DietaryAgentService.class);
    private final ImageStorageService imageStorageService = mock(ImageStorageService.class);
    private final DietRecordService service = new DietRecordService(
            dietRecordRepository,
            userRepository,
            dietaryAgentService,
            imageStorageService
    );

    @Test
    void updateKeepsExistingNutritionWhenRequestOmitsFields() {
        DietRecord record = existingRecord();
        when(dietRecordRepository.findById(10L)).thenReturn(Optional.of(record));
        when(dietRecordRepository.save(record)).thenReturn(record);

        DietRecordRequest request = new DietRecordRequest();
        request.setDescription("updated");

        DietRecord result = service.update(10L, 1L, request);

        assertThat(result.getDishName()).isEqualTo("Chicken Box");
        assertThat(result.getCalories()).isEqualTo(550.0);
        assertThat(result.getProtein()).isEqualTo(35.0);
        assertThat(result.getFat()).isEqualTo(12.0);
        assertThat(result.getCarbohydrates()).isEqualTo(48.0);
        assertThat(result.getDescription()).isEqualTo("updated");
    }

    @Test
    void updateRefreshesNutritionWhenDishNameChangesAndNutritionNotProvided() {
        DietRecord record = existingRecord();
        when(dietRecordRepository.findById(10L)).thenReturn(Optional.of(record));
        when(dietRecordRepository.save(record)).thenReturn(record);
        when(dietaryAgentService.fetchDishNutrition("Salmon Bowl"))
                .thenReturn(new DietaryAgentService.NutritionValues(620.0, 40.0, 18.0, 45.0));

        DietRecordRequest request = new DietRecordRequest();
        request.setDishName("Salmon Bowl");

        DietRecord result = service.update(10L, 1L, request);

        assertThat(result.getDishName()).isEqualTo("Salmon Bowl");
        assertThat(result.getCalories()).isEqualTo(620.0);
        assertThat(result.getProtein()).isEqualTo(40.0);
        assertThat(result.getFat()).isEqualTo(18.0);
        assertThat(result.getCarbohydrates()).isEqualTo(45.0);
        verify(dietaryAgentService).fetchDishNutrition("Salmon Bowl");
    }

    private DietRecord existingRecord() {
        User user = User.builder().id(1L).email("user@example.com").password("encoded").build();
        return DietRecord.builder()
                .id(10L)
                .user(user)
                .dishName("Chicken Box")
                .calories(550.0)
                .protein(35.0)
                .fat(12.0)
                .carbohydrates(48.0)
                .mealType("LUNCH")
                .description("original")
                .build();
    }
}
