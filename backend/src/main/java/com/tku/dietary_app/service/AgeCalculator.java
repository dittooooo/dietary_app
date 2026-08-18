package com.tku.dietary_app.service;

import java.time.LocalDate;
import java.time.Period;

public final class AgeCalculator {
    private AgeCalculator() {
    }

    public static Integer calculateAge(LocalDate birthDate) {
        if (birthDate == null) {
            return null;
        }
        return Period.between(birthDate, LocalDate.now()).getYears();
    }

    public static Integer calculateAge(LocalDate birthDate, Integer fallbackAge) {
        Integer computedAge = calculateAge(birthDate);
        return computedAge != null ? computedAge : fallbackAge;
    }
}
