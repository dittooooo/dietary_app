package com.tku.dietary_app.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import lombok.Builder;
import lombok.Data;

import java.util.List;

@Data
@Builder
@JsonPropertyOrder({"question", "question_type", "dish_names", "user_profile"})
public class DietaryAgentPayload {

    private String question;

    @JsonProperty("question_type")
    private String question_type;

    @JsonProperty("dish_names")
    private List<String> dish_names;

    @JsonProperty("user_profile")
    private UserProfileDto user_profile;

    @Data
    @Builder
    @JsonPropertyOrder({"height_cm", "weight_kg", "gender", "age", "recommended_calorie"})
    public static class UserProfileDto {
        @JsonProperty("height_cm")
        private Double height_cm;

        @JsonProperty("weight_kg")
        private Double weight_kg;

        private String gender;
        private Integer age;

        @JsonProperty("recommended_calorie")
        private Integer recommended_calorie;
    }
}
