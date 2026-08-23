IF COL_LENGTH('dbo.diet_records', 'meal_date') IS NULL
BEGIN
    ALTER TABLE dbo.diet_records ADD meal_date DATE NULL;
END;
GO

UPDATE dbo.diet_records
SET meal_date = record_date
WHERE meal_date IS NULL AND record_date IS NOT NULL;
GO

UPDATE dbo.diet_records
SET meal_date = CAST(created_at AS DATE)
WHERE meal_date IS NULL AND created_at IS NOT NULL;
GO

UPDATE dbo.diet_records
SET meal_date = CAST(GETDATE() AS DATE)
WHERE meal_date IS NULL;
GO

ALTER TABLE dbo.diet_records ALTER COLUMN meal_date DATE NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'idx_diet_records_user_meal_date'
      AND object_id = OBJECT_ID(N'dbo.diet_records')
)
BEGIN
    CREATE INDEX idx_diet_records_user_meal_date
    ON dbo.diet_records (user_id, meal_date);
END;
