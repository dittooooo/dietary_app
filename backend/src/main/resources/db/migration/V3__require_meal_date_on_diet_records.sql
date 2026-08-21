ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS meal_date DATE;

UPDATE diet_records
SET meal_date = record_date
WHERE meal_date IS NULL AND record_date IS NOT NULL;

UPDATE diet_records
SET meal_date = created_at::DATE
WHERE meal_date IS NULL AND created_at IS NOT NULL;

UPDATE diet_records
SET meal_date = CURRENT_DATE
WHERE meal_date IS NULL;

ALTER TABLE diet_records ALTER COLUMN meal_date SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_diet_records_user_meal_date
ON diet_records (user_id, meal_date);
