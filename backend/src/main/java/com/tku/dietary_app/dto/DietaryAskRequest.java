package com.tku.dietary_app.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import lombok.Data;
import java.util.List;

@Data
public class DietaryAskRequest {
    private String question;

    @JsonProperty("question_type")
    @NotBlank(message = "questionType 為必填")
    private String questionType;

    @JsonProperty("dish_names")
    @NotEmpty(message = "dishNames 為必填，且至少需要一筆")
    private List<String> dishNames;
}
