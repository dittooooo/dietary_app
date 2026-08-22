IF OBJECT_ID(N'dbo.users', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.users (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        email VARCHAR(255) NOT NULL UNIQUE,
        password VARCHAR(255) NOT NULL,
        role VARCHAR(255) NOT NULL CONSTRAINT DF_users_role DEFAULT 'ROLE_USER',
        has_completed_onboarding BIT NOT NULL CONSTRAINT DF_users_has_completed_onboarding DEFAULT 0,
        refresh_token_hash VARCHAR(255) NULL,
        refresh_token_expires_at DATETIME2 NULL,
        created_at DATETIME2 NOT NULL CONSTRAINT DF_users_created_at DEFAULT CURRENT_TIMESTAMP
    );
END;

IF COL_LENGTH('dbo.users', 'role') IS NULL ALTER TABLE dbo.users ADD role VARCHAR(255) NULL;
IF COL_LENGTH('dbo.users', 'has_completed_onboarding') IS NULL ALTER TABLE dbo.users ADD has_completed_onboarding BIT NULL;
IF COL_LENGTH('dbo.users', 'refresh_token_hash') IS NULL ALTER TABLE dbo.users ADD refresh_token_hash VARCHAR(255) NULL;
IF COL_LENGTH('dbo.users', 'refresh_token_expires_at') IS NULL ALTER TABLE dbo.users ADD refresh_token_expires_at DATETIME2 NULL;
IF COL_LENGTH('dbo.users', 'created_at') IS NULL ALTER TABLE dbo.users ADD created_at DATETIME2 NULL;

UPDATE dbo.users
SET role = 'ROLE_USER'
WHERE role IS NULL OR LTRIM(RTRIM(role)) = '';

UPDATE dbo.users
SET has_completed_onboarding = 0
WHERE has_completed_onboarding IS NULL;

UPDATE dbo.users
SET created_at = CURRENT_TIMESTAMP
WHERE created_at IS NULL;

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.users')
      AND c.name = 'role'
)
BEGIN
    ALTER TABLE dbo.users ADD CONSTRAINT DF_users_role DEFAULT 'ROLE_USER' FOR role;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.users')
      AND c.name = 'has_completed_onboarding'
)
BEGIN
    ALTER TABLE dbo.users ADD CONSTRAINT DF_users_has_completed_onboarding DEFAULT 0 FOR has_completed_onboarding;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.users')
      AND c.name = 'created_at'
)
BEGIN
    ALTER TABLE dbo.users ADD CONSTRAINT DF_users_created_at DEFAULT CURRENT_TIMESTAMP FOR created_at;
END;

ALTER TABLE dbo.users ALTER COLUMN role VARCHAR(255) NOT NULL;
ALTER TABLE dbo.users ALTER COLUMN has_completed_onboarding BIT NOT NULL;
ALTER TABLE dbo.users ALTER COLUMN created_at DATETIME2 NOT NULL;

IF OBJECT_ID(N'dbo.user_profile', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.user_profile (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        user_id BIGINT NOT NULL UNIQUE,
        nickname VARCHAR(255) NOT NULL,
        gender VARCHAR(255) NOT NULL,
        age INT NOT NULL,
        height FLOAT NOT NULL,
        weight FLOAT NOT NULL,
        health_conditions VARCHAR(MAX) NOT NULL,
        diet_goal VARCHAR(255) NOT NULL,
        pet_type VARCHAR(255) NOT NULL,
        avatar_url VARCHAR(255) NULL,
        bmr FLOAT NULL,
        tdee FLOAT NULL,
        recommended_calories FLOAT NULL,
        body_score INT NOT NULL CONSTRAINT DF_user_profile_body_score DEFAULT 50,
        muscle_score INT NOT NULL CONSTRAINT DF_user_profile_muscle_score DEFAULT 50,
        body_type VARCHAR(255) NOT NULL CONSTRAINT DF_user_profile_body_type DEFAULT 'NORMAL',
        last_settle_date DATE NULL,
        created_at DATETIME2 NOT NULL CONSTRAINT DF_user_profile_created_at DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME2 NOT NULL CONSTRAINT DF_user_profile_updated_at DEFAULT CURRENT_TIMESTAMP
    );
END;

IF COL_LENGTH('dbo.user_profile', 'avatar_url') IS NULL ALTER TABLE dbo.user_profile ADD avatar_url VARCHAR(255) NULL;
IF COL_LENGTH('dbo.user_profile', 'bmr') IS NULL ALTER TABLE dbo.user_profile ADD bmr FLOAT NULL;
IF COL_LENGTH('dbo.user_profile', 'tdee') IS NULL ALTER TABLE dbo.user_profile ADD tdee FLOAT NULL;
IF COL_LENGTH('dbo.user_profile', 'recommended_calories') IS NULL ALTER TABLE dbo.user_profile ADD recommended_calories FLOAT NULL;
IF COL_LENGTH('dbo.user_profile', 'body_score') IS NULL ALTER TABLE dbo.user_profile ADD body_score INT NULL;
IF COL_LENGTH('dbo.user_profile', 'muscle_score') IS NULL ALTER TABLE dbo.user_profile ADD muscle_score INT NULL;
IF COL_LENGTH('dbo.user_profile', 'body_type') IS NULL ALTER TABLE dbo.user_profile ADD body_type VARCHAR(255) NULL;
IF COL_LENGTH('dbo.user_profile', 'last_settle_date') IS NULL ALTER TABLE dbo.user_profile ADD last_settle_date DATE NULL;
IF COL_LENGTH('dbo.user_profile', 'created_at') IS NULL ALTER TABLE dbo.user_profile ADD created_at DATETIME2 NULL;
IF COL_LENGTH('dbo.user_profile', 'updated_at') IS NULL ALTER TABLE dbo.user_profile ADD updated_at DATETIME2 NULL;

UPDATE dbo.user_profile
SET body_score = 50
WHERE body_score IS NULL;

UPDATE dbo.user_profile
SET muscle_score = 50
WHERE muscle_score IS NULL;

UPDATE dbo.user_profile
SET body_type = 'NORMAL'
WHERE body_type IS NULL OR LTRIM(RTRIM(body_type)) = '' OR UPPER(body_type) = 'STANDARD';

UPDATE dbo.user_profile
SET created_at = CURRENT_TIMESTAMP
WHERE created_at IS NULL;

UPDATE dbo.user_profile
SET updated_at = CURRENT_TIMESTAMP
WHERE updated_at IS NULL;

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.user_profile')
      AND c.name = 'body_score'
)
BEGIN
    ALTER TABLE dbo.user_profile ADD CONSTRAINT DF_user_profile_body_score DEFAULT 50 FOR body_score;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.user_profile')
      AND c.name = 'muscle_score'
)
BEGIN
    ALTER TABLE dbo.user_profile ADD CONSTRAINT DF_user_profile_muscle_score DEFAULT 50 FOR muscle_score;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.user_profile')
      AND c.name = 'body_type'
)
BEGIN
    ALTER TABLE dbo.user_profile ADD CONSTRAINT DF_user_profile_body_type DEFAULT 'NORMAL' FOR body_type;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.user_profile')
      AND c.name = 'created_at'
)
BEGIN
    ALTER TABLE dbo.user_profile ADD CONSTRAINT DF_user_profile_created_at DEFAULT CURRENT_TIMESTAMP FOR created_at;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.user_profile')
      AND c.name = 'updated_at'
)
BEGIN
    ALTER TABLE dbo.user_profile ADD CONSTRAINT DF_user_profile_updated_at DEFAULT CURRENT_TIMESTAMP FOR updated_at;
END;

ALTER TABLE dbo.user_profile ALTER COLUMN body_score INT NOT NULL;
ALTER TABLE dbo.user_profile ALTER COLUMN muscle_score INT NOT NULL;
ALTER TABLE dbo.user_profile ALTER COLUMN body_type VARCHAR(255) NOT NULL;
ALTER TABLE dbo.user_profile ALTER COLUMN created_at DATETIME2 NOT NULL;
ALTER TABLE dbo.user_profile ALTER COLUMN updated_at DATETIME2 NOT NULL;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'fk_user_profile_user'
      AND parent_object_id = OBJECT_ID(N'dbo.user_profile')
)
BEGIN
    ALTER TABLE dbo.user_profile
    ADD CONSTRAINT fk_user_profile_user FOREIGN KEY (user_id) REFERENCES dbo.users (id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'uk_user_profile_user_id'
      AND object_id = OBJECT_ID(N'dbo.user_profile')
)
BEGIN
    CREATE UNIQUE INDEX uk_user_profile_user_id ON dbo.user_profile (user_id);
END;

IF OBJECT_ID(N'dbo.diet_records', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.diet_records (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        user_id BIGINT NOT NULL,
        dish_name VARCHAR(255) NOT NULL,
        calories FLOAT NULL,
        protein FLOAT NULL,
        fat FLOAT NULL,
        carbohydrates FLOAT NULL,
        record_date DATE NULL,
        description VARCHAR(255) NULL,
        photo_url VARCHAR(255) NULL,
        meal_type VARCHAR(255) NOT NULL,
        created_at DATETIME2 NOT NULL CONSTRAINT DF_diet_records_created_at DEFAULT CURRENT_TIMESTAMP
    );
END;

IF COL_LENGTH('dbo.diet_records', 'calories') IS NULL ALTER TABLE dbo.diet_records ADD calories FLOAT NULL;
IF COL_LENGTH('dbo.diet_records', 'protein') IS NULL ALTER TABLE dbo.diet_records ADD protein FLOAT NULL;
IF COL_LENGTH('dbo.diet_records', 'fat') IS NULL ALTER TABLE dbo.diet_records ADD fat FLOAT NULL;
IF COL_LENGTH('dbo.diet_records', 'carbohydrates') IS NULL ALTER TABLE dbo.diet_records ADD carbohydrates FLOAT NULL;
IF COL_LENGTH('dbo.diet_records', 'record_date') IS NULL ALTER TABLE dbo.diet_records ADD record_date DATE NULL;
IF COL_LENGTH('dbo.diet_records', 'description') IS NULL ALTER TABLE dbo.diet_records ADD description VARCHAR(255) NULL;
IF COL_LENGTH('dbo.diet_records', 'photo_url') IS NULL ALTER TABLE dbo.diet_records ADD photo_url VARCHAR(255) NULL;
IF COL_LENGTH('dbo.diet_records', 'meal_type') IS NULL ALTER TABLE dbo.diet_records ADD meal_type VARCHAR(255) NULL;
IF COL_LENGTH('dbo.diet_records', 'created_at') IS NULL ALTER TABLE dbo.diet_records ADD created_at DATETIME2 NULL;

UPDATE dbo.diet_records
SET created_at = CURRENT_TIMESTAMP
WHERE created_at IS NULL;

UPDATE dbo.diet_records
SET record_date = CAST(created_at AS DATE)
WHERE record_date IS NULL AND created_at IS NOT NULL;

UPDATE dbo.diet_records
SET meal_type = 'UNKNOWN'
WHERE meal_type IS NULL OR LTRIM(RTRIM(meal_type)) = '';

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.diet_records')
      AND c.name = 'created_at'
)
BEGIN
    ALTER TABLE dbo.diet_records ADD CONSTRAINT DF_diet_records_created_at DEFAULT CURRENT_TIMESTAMP FOR created_at;
END;

ALTER TABLE dbo.diet_records ALTER COLUMN created_at DATETIME2 NOT NULL;
ALTER TABLE dbo.diet_records ALTER COLUMN meal_type VARCHAR(255) NOT NULL;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'fk_diet_records_user'
      AND parent_object_id = OBJECT_ID(N'dbo.diet_records')
)
BEGIN
    ALTER TABLE dbo.diet_records
    ADD CONSTRAINT fk_diet_records_user FOREIGN KEY (user_id) REFERENCES dbo.users (id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'idx_diet_records_user_id'
      AND object_id = OBJECT_ID(N'dbo.diet_records')
)
BEGIN
    CREATE INDEX idx_diet_records_user_id ON dbo.diet_records (user_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'idx_diet_records_record_date'
      AND object_id = OBJECT_ID(N'dbo.diet_records')
)
BEGIN
    CREATE INDEX idx_diet_records_record_date ON dbo.diet_records (record_date);
END;

IF OBJECT_ID(N'dbo.menu_item', N'U') IS NOT NULL DROP TABLE dbo.menu_item;
IF OBJECT_ID(N'dbo.menu_items', N'U') IS NOT NULL DROP TABLE dbo.menu_items;
IF OBJECT_ID(N'dbo.restaurant', N'U') IS NOT NULL DROP TABLE dbo.restaurant;
IF OBJECT_ID(N'dbo.restaurants', N'U') IS NOT NULL DROP TABLE dbo.restaurants;
