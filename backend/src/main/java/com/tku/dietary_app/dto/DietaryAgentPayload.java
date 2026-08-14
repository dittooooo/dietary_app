package com.tku.dietary_app.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import lombok.Builder;
import lombok.Data;

import java.time.LocalDate;
import java.util.List;

@Data
@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonPropertyOrder({"question", "question_type", "dish_info_list", "user_profile", "health_condition", "weekly_diet_records"})
public class DietaryAgentPayload {

    private String question;

    @JsonProperty("question_type")
    private String questionType;

    @JsonProperty("dish_info_list")
    private List<DishInfoDto> dishInfoList;

    @JsonProperty("user_profile")
    private UserProfileDto userProfile;

    @JsonProperty("health_condition")
    private HealthConditionDto healthCondition;

    @JsonProperty("weekly_diet_records")
    private List<WeeklyDietRecordDto> weeklyDietRecords;

    @Data
    @Builder
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonPropertyOrder({"height_cm", "weight_kg", "gender", "age"})
    public static class UserProfileDto {
        @JsonProperty("height_cm")
        private Double heightCm;

        @JsonProperty("weight_kg")
        private Double weightKg;

        private String gender;
        private Integer age;
    }

    @Data
    @Builder
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonPropertyOrder({"has_chronic_disease", "chronic_diseases"})
    public static class HealthConditionDto {
        @JsonProperty("has_chronic_disease")
        private Boolean hasChronicDisease;

        @JsonProperty("chronic_diseases")
        private List<String> chronicDiseases;
    }

    @Data
    @Builder
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonPropertyOrder({"date", "meal", "dish_name", "note"})
    public static class WeeklyDietRecordDto {
        private LocalDate date;
        private String meal;

        @JsonProperty("dish_name")
        private String dishName;

        private String note;
    }

    @Data
    @Builder
    @JsonInclude(JsonInclude.Include.NON_NULL)
    @JsonPropertyOrder({"dish_name", "amount"})
    public static class DishInfoDto {
        @JsonProperty("dish_name")
        private String dishName;

        private Integer amount;
    }
}
