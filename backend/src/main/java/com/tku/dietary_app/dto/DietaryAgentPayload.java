package com.tku.dietary_app.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import lombok.Builder;
import lombok.Data;

import java.util.List;

@Data
@Builder
@JsonPropertyOrder({"question", "user_profile", "health_condition", "weekly_diet_records"})
public class DietaryAgentPayload {

    private String question;

    @JsonProperty("user_profile")
    private UserProfileDto userProfile;

    @JsonProperty("health_condition")
    private HealthConditionDto healthCondition;

    @JsonProperty("weekly_diet_records")
    private List<DietRecordDto> weeklyDietRecords;

    @Data
    @Builder
    public static class UserProfileDto {
        @JsonProperty("height_cm")
        private Double heightCm;

        @JsonProperty("weight_kg")
        private Double weightKg;

        private String gender;
        private Integer age;
        private String goal;
    }

    @Data
    @Builder
    public static class HealthConditionDto {
        @JsonProperty("has_chronic_disease")
        private boolean hasChronicDisease;

        @JsonProperty("chronic_diseases")
        private List<String> chronicDiseases;
    }

    @Data
    @Builder
    public static class DietRecordDto {
        private String date;
        private String meal;

        @JsonProperty("dish_name")
        private String dishName;

        @JsonProperty("note")
        private String description;
    }
}
