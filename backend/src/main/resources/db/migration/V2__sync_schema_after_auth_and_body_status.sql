ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS has_completed_onboarding BOOLEAN;
ALTER TABLE users ADD COLUMN IF NOT EXISTS refresh_token_hash VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS refresh_token_expires_at TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMP;

UPDATE users
SET role = 'ROLE_USER'
WHERE role IS NULL OR BTRIM(role) = '';

UPDATE users
SET has_completed_onboarding = FALSE
WHERE has_completed_onboarding IS NULL;

UPDATE users
SET created_at = CURRENT_TIMESTAMP
WHERE created_at IS NULL;

ALTER TABLE users ALTER COLUMN role SET DEFAULT 'ROLE_USER';
ALTER TABLE users ALTER COLUMN has_completed_onboarding SET DEFAULT FALSE;
ALTER TABLE users ALTER COLUMN has_completed_onboarding SET NOT NULL;
ALTER TABLE users ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(255);
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS bmr DOUBLE PRECISION;
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS tdee DOUBLE PRECISION;
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS recommended_calories DOUBLE PRECISION;
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS body_score INTEGER;
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS muscle_score INTEGER;
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS body_type VARCHAR(255);
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS last_settle_date DATE;
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS created_at TIMESTAMP;
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP;

UPDATE user_profile
SET body_score = 50
WHERE body_score IS NULL;

UPDATE user_profile
SET muscle_score = 50
WHERE muscle_score IS NULL;

UPDATE user_profile
SET body_type = 'NORMAL'
WHERE body_type IS NULL OR BTRIM(body_type) = '' OR UPPER(body_type) = 'STANDARD';

UPDATE user_profile
SET created_at = CURRENT_TIMESTAMP
WHERE created_at IS NULL;

UPDATE user_profile
SET updated_at = CURRENT_TIMESTAMP
WHERE updated_at IS NULL;

ALTER TABLE user_profile ALTER COLUMN body_score SET DEFAULT 50;
ALTER TABLE user_profile ALTER COLUMN body_score SET NOT NULL;
ALTER TABLE user_profile ALTER COLUMN muscle_score SET DEFAULT 50;
ALTER TABLE user_profile ALTER COLUMN muscle_score SET NOT NULL;
ALTER TABLE user_profile ALTER COLUMN body_type SET DEFAULT 'NORMAL';
ALTER TABLE user_profile ALTER COLUMN body_type SET NOT NULL;
ALTER TABLE user_profile ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE user_profile ALTER COLUMN created_at SET NOT NULL;
ALTER TABLE user_profile ALTER COLUMN updated_at SET DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE user_profile ALTER COLUMN updated_at SET NOT NULL;

ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS calories DOUBLE PRECISION;
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS protein DOUBLE PRECISION;
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS fat DOUBLE PRECISION;
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS carbohydrates DOUBLE PRECISION;
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS record_date DATE;
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS description VARCHAR(255);
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS photo_url VARCHAR(255);
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS meal_type VARCHAR(255);
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS amount INTEGER;
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS created_at TIMESTAMP;

UPDATE diet_records
SET created_at = CURRENT_TIMESTAMP
WHERE created_at IS NULL;

UPDATE diet_records
SET record_date = created_at::DATE
WHERE record_date IS NULL AND created_at IS NOT NULL;

UPDATE diet_records
SET meal_type = 'UNKNOWN'
WHERE meal_type IS NULL OR BTRIM(meal_type) = '';

UPDATE diet_records
SET amount = 1
WHERE amount IS NULL;

ALTER TABLE diet_records ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE diet_records ALTER COLUMN created_at SET NOT NULL;
ALTER TABLE diet_records ALTER COLUMN meal_type SET NOT NULL;
ALTER TABLE diet_records ALTER COLUMN amount SET DEFAULT 1;
ALTER TABLE diet_records ALTER COLUMN amount SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uk_user_profile_user_id ON user_profile (user_id);
CREATE INDEX IF NOT EXISTS idx_diet_records_user_id ON diet_records (user_id);
CREATE INDEX IF NOT EXISTS idx_diet_records_record_date ON diet_records (record_date);
