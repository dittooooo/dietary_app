package com.tku.dietary_app.config;

import lombok.RequiredArgsConstructor;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class DietRecordDateBackfill {

    private final JdbcTemplate jdbcTemplate;

    @EventListener(ApplicationReadyEvent.class)
    public void backfillRecordDate() {
        jdbcTemplate.update("""
                UPDATE diet_records
                SET record_date = created_at::date
                WHERE record_date IS NULL
                  AND created_at IS NOT NULL
                """);
    }
}
