ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS birth_date DATE;

UPDATE user_profile
SET birth_date = CURRENT_DATE - make_interval(years => age)
WHERE birth_date IS NULL AND age IS NOT NULL AND age > 0;
