CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    role VARCHAR(255) DEFAULT 'ROLE_USER',
    has_completed_onboarding BOOLEAN NOT NULL DEFAULT FALSE,
    refresh_token_hash VARCHAR(255),
    refresh_token_expires_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

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
ALTER TABLE users ALTER COLUMN created_at SET NOT NULL;

CREATE TABLE IF NOT EXISTS user_profile (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE,
    nickname VARCHAR(255) NOT NULL,
    gender VARCHAR(255) NOT NULL,
    age INTEGER NOT NULL,
    height DOUBLE PRECISION NOT NULL,
    weight DOUBLE PRECISION NOT NULL,
    health_conditions TEXT NOT NULL,
    diet_goal VARCHAR(255) NOT NULL,
    pet_type VARCHAR(255) NOT NULL,
    avatar_url VARCHAR(255),
    bmr DOUBLE PRECISION,
    tdee DOUBLE PRECISION,
    recommended_calories DOUBLE PRECISION,
    body_score INTEGER NOT NULL DEFAULT 50,
    muscle_score INTEGER NOT NULL DEFAULT 50,
    body_type VARCHAR(255) NOT NULL DEFAULT 'NORMAL',
    last_settle_date DATE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_user_profile_user FOREIGN KEY (user_id) REFERENCES users (id)
);

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

CREATE UNIQUE INDEX IF NOT EXISTS uk_user_profile_user_id ON user_profile (user_id);

CREATE TABLE IF NOT EXISTS diet_records (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    dish_name VARCHAR(255) NOT NULL,
    calories DOUBLE PRECISION,
    protein DOUBLE PRECISION,
    fat DOUBLE PRECISION,
    carbohydrates DOUBLE PRECISION,
    record_date DATE,
    description VARCHAR(255),
    photo_url VARCHAR(255),
    meal_type VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_diet_records_user FOREIGN KEY (user_id) REFERENCES users (id)
);

ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS calories DOUBLE PRECISION;
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS protein DOUBLE PRECISION;
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS fat DOUBLE PRECISION;
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS carbohydrates DOUBLE PRECISION;
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS record_date DATE;
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS description VARCHAR(255);
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS photo_url VARCHAR(255);
ALTER TABLE diet_records ADD COLUMN IF NOT EXISTS meal_type VARCHAR(255);
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

ALTER TABLE diet_records ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE diet_records ALTER COLUMN created_at SET NOT NULL;
ALTER TABLE diet_records ALTER COLUMN meal_type SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_diet_records_user_id ON diet_records (user_id);
CREATE INDEX IF NOT EXISTS idx_diet_records_record_date ON diet_records (record_date);

DROP TABLE IF EXISTS menu_item CASCADE;
DROP TABLE IF EXISTS menu_items CASCADE;
DROP TABLE IF EXISTS restaurant CASCADE;
DROP TABLE IF EXISTS restaurants CASCADE;
