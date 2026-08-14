package com.tku.dietary_app.service;

import com.tku.dietary_app.dto.DietRecordRequest;
import com.tku.dietary_app.entity.DietRecord;
import com.tku.dietary_app.entity.User;
import com.tku.dietary_app.repository.DietRecordRepository;
import com.tku.dietary_app.repository.UserRepository;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
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
        assertThat(result.getAmount()).isEqualTo(1);
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
        assertThat(result.getAmount()).isEqualTo(1);
        verify(dietaryAgentService).fetchDishNutrition("Salmon Bowl");
    }

    @Test
    void createDefaultsAmountToOneWhenRequestAmountIsNull() {
        User user = User.builder().id(1L).email("user@example.com").password("encoded").build();
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(dietaryAgentService.fetchDishNutrition("Chicken Box"))
                .thenReturn(new DietaryAgentService.NutritionValues(550.0, 35.0, 12.0, 48.0));
        when(dietRecordRepository.save(org.mockito.ArgumentMatchers.any(DietRecord.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        DietRecordRequest request = new DietRecordRequest();
        request.setDishName("Chicken Box");
        request.setMealType("LUNCH");
        request.setDate(LocalDate.of(2026, 8, 12));

        DietRecord result = service.create(1L, request);

        assertThat(result.getAmount()).isEqualTo(1);
    }

    @Test
    void updateSetsAmountToOneWhenExistingAmountIsNullAndRequestOmitsAmount() {
        DietRecord record = existingRecord();
        record.setAmount(null);
        when(dietRecordRepository.findById(10L)).thenReturn(Optional.of(record));
        when(dietRecordRepository.save(record)).thenReturn(record);

        DietRecordRequest request = new DietRecordRequest();
        request.setDescription("updated");

        DietRecord result = service.update(10L, 1L, request);

        assertThat(result.getAmount()).isEqualTo(1);
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
                .amount(2)
                .description("original")
                .build();
    }
}
