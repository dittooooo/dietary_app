IF OBJECT_ID(N'dbo.user_custom_dishes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.user_custom_dishes (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        user_id BIGINT NOT NULL,
        dish_name VARCHAR(255) NOT NULL,
        calories FLOAT NOT NULL,
        protein FLOAT NOT NULL,
        fat FLOAT NOT NULL,
        carbohydrates FLOAT NOT NULL,
        type VARCHAR(50) NOT NULL CONSTRAINT DF_user_custom_dishes_type DEFAULT 'MANUAL',
        created_at DATETIME2 NOT NULL CONSTRAINT DF_user_custom_dishes_created_at DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME2 NOT NULL CONSTRAINT DF_user_custom_dishes_updated_at DEFAULT CURRENT_TIMESTAMP
    );
END;

IF COL_LENGTH('dbo.user_custom_dishes', 'type') IS NULL ALTER TABLE dbo.user_custom_dishes ADD type VARCHAR(50) NULL;
IF COL_LENGTH('dbo.user_custom_dishes', 'created_at') IS NULL ALTER TABLE dbo.user_custom_dishes ADD created_at DATETIME2 NULL;
IF COL_LENGTH('dbo.user_custom_dishes', 'updated_at') IS NULL ALTER TABLE dbo.user_custom_dishes ADD updated_at DATETIME2 NULL;

UPDATE dbo.user_custom_dishes
SET type = 'MANUAL'
WHERE type IS NULL OR LTRIM(RTRIM(type)) = '';

UPDATE dbo.user_custom_dishes
SET created_at = CURRENT_TIMESTAMP
WHERE created_at IS NULL;

UPDATE dbo.user_custom_dishes
SET updated_at = CURRENT_TIMESTAMP
WHERE updated_at IS NULL;

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.user_custom_dishes')
      AND c.name = 'type'
)
BEGIN
    ALTER TABLE dbo.user_custom_dishes ADD CONSTRAINT DF_user_custom_dishes_type DEFAULT 'MANUAL' FOR type;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.user_custom_dishes')
      AND c.name = 'created_at'
)
BEGIN
    ALTER TABLE dbo.user_custom_dishes ADD CONSTRAINT DF_user_custom_dishes_created_at DEFAULT CURRENT_TIMESTAMP FOR created_at;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.user_custom_dishes')
      AND c.name = 'updated_at'
)
BEGIN
    ALTER TABLE dbo.user_custom_dishes ADD CONSTRAINT DF_user_custom_dishes_updated_at DEFAULT CURRENT_TIMESTAMP FOR updated_at;
END;

ALTER TABLE dbo.user_custom_dishes ALTER COLUMN type VARCHAR(50) NOT NULL;
ALTER TABLE dbo.user_custom_dishes ALTER COLUMN created_at DATETIME2 NOT NULL;
ALTER TABLE dbo.user_custom_dishes ALTER COLUMN updated_at DATETIME2 NOT NULL;

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'fk_user_custom_dishes_user'
      AND parent_object_id = OBJECT_ID(N'dbo.user_custom_dishes')
)
BEGIN
    ALTER TABLE dbo.user_custom_dishes
    ADD CONSTRAINT fk_user_custom_dishes_user FOREIGN KEY (user_id) REFERENCES dbo.users (id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'idx_user_custom_dishes_user_id'
      AND object_id = OBJECT_ID(N'dbo.user_custom_dishes')
)
BEGIN
    CREATE INDEX idx_user_custom_dishes_user_id ON dbo.user_custom_dishes (user_id);
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'uk_user_custom_dishes_user_name'
      AND object_id = OBJECT_ID(N'dbo.user_custom_dishes')
)
BEGIN
    CREATE UNIQUE INDEX uk_user_custom_dishes_user_name ON dbo.user_custom_dishes (user_id, dish_name);
END;
