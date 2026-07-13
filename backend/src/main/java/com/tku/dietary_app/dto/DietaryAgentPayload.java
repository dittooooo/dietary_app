package com.tku.dietary_app.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import lombok.Builder;
import lombok.Data;

import java.util.List;

@Data
@Builder
@JsonPropertyOrder({"question", "question_type", "dish_names", "user_profile", "health_condition", "weekly_diet_records"})
public class DietaryAgentPayload {

    private String question;

    @JsonProperty("question_type")
    private String question_type;

    @JsonProperty("dish_names")
    private List<String> dish_names;

    @JsonProperty("user_profile")
    private UserProfileDto user_profile;

    @JsonProperty("health_condition")
    private HealthConditionDto health_condition;

    @JsonProperty("weekly_diet_records")
    private List<DietRecordDto> weekly_diet_records;

    @Data
    @Builder
    public static class UserProfileDto {
        @JsonProperty("height_cm")
        private Double height_cm;

        @JsonProperty("weight_kg")
        private Double weight_kg;

        private String gender;
        private Integer age;
        private String goal;
    }

    @Data
    @Builder
    public static class HealthConditionDto {
        @JsonProperty("has_chronic_disease")
        private boolean has_chronic_disease;

        @JsonProperty("chronic_diseases")
        private List<String> chronic_diseases;
    }

    @Data
    @Builder
    public static class DietRecordDto {
        private String date;
        private String meal;

        @JsonProperty("dish_name")
        private String dish_name;

        @JsonProperty("note")
        private String note;
    }
}
