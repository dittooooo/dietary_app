IF COL_LENGTH('dbo.problem_feedback', 'admin_reply') IS NULL
BEGIN
    ALTER TABLE dbo.problem_feedback ADD admin_reply VARCHAR(MAX) NULL;
END;
GO

IF COL_LENGTH('dbo.problem_feedback', 'replied_at') IS NULL
BEGIN
    ALTER TABLE dbo.problem_feedback ADD replied_at DATETIME2 NULL;
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'idx_problem_feedback_created_at'
      AND object_id = OBJECT_ID(N'dbo.problem_feedback')
)
BEGIN
    CREATE INDEX idx_problem_feedback_created_at
    ON dbo.problem_feedback (created_at DESC);
END;
