IF COL_LENGTH('dbo.problem_feedback', 'photo_url') IS NULL
BEGIN
    ALTER TABLE dbo.problem_feedback ADD photo_url VARCHAR(512) NULL;
END;
