package com.tku.dietary_app.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.Data;

import java.time.LocalDate;
import java.util.List;

@Data
@JsonInclude(JsonInclude.Include.NON_NULL)
public class DietaryAskRequest {
    private String question;

    @JsonProperty("question_type")
    @NotBlank(message = "questionType 為必填")
    private String questionType;

    @JsonProperty("dish_info_list")
    @NotEmpty(message = "dishInfoList 為必填，且至少需要一筆")
    @Valid
    private List<DishInfoDto> dishInfoList;

    @JsonProperty("user_profile")
    private UserProfileDto userProfile;

    @JsonProperty("health_condition")
    private HealthConditionDto healthCondition;

    @JsonProperty("weekly_diet_records")
    private List<WeeklyDietRecordDto> weeklyDietRecords;

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class UserProfileDto {
        @JsonProperty("height_cm")
        private Double heightCm;

        @JsonProperty("weight_kg")
        private Double weightKg;

        private String gender;
        private Integer age;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class HealthConditionDto {
        @JsonProperty("has_chronic_disease")
        private Boolean hasChronicDisease;

        @JsonProperty("chronic_diseases")
        private List<String> chronicDiseases;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class WeeklyDietRecordDto {
        private LocalDate date;
        private String meal;

        @JsonProperty("dish_name")
        private String dishName;

        private String note;
    }

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class DishInfoDto {
        @JsonProperty("dish_name")
        @NotBlank(message = "dish_name 為必填")
        private String dishName;

        @NotNull(message = "amount 為必填")
        @Positive(message = "amount 必須大於 0")
        private Integer amount;
    }
}
