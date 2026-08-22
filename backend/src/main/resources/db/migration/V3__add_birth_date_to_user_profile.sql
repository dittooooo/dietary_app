IF COL_LENGTH('dbo.user_profile', 'birth_date') IS NULL
BEGIN
    ALTER TABLE dbo.user_profile ADD birth_date DATE NULL;
END;
GO

UPDATE dbo.user_profile
SET birth_date = DATEADD(YEAR, -age, CAST(GETDATE() AS DATE))
WHERE birth_date IS NULL AND age IS NOT NULL AND age > 0;
