ALTER TABLE diet_records
ADD COLUMN IF NOT EXISTS meal_date date;

UPDATE diet_records
SET meal_date = created_at::date
WHERE meal_date IS NULL;

ALTER TABLE diet_records
ALTER COLUMN meal_date SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_diet_records_user_meal_date
ON diet_records (user_id, meal_date);
