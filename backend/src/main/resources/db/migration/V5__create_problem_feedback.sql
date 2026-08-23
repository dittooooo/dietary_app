IF OBJECT_ID(N'dbo.problem_feedback', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.problem_feedback (
        id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        user_id BIGINT NOT NULL,
        user_name VARCHAR(255) NOT NULL,
        content VARCHAR(MAX) NOT NULL,
        created_at DATETIME2 NOT NULL CONSTRAINT DF_problem_feedback_created_at DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME2 NOT NULL CONSTRAINT DF_problem_feedback_updated_at DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT fk_problem_feedback_user FOREIGN KEY (user_id) REFERENCES dbo.users (id)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'idx_problem_feedback_user_created_at'
      AND object_id = OBJECT_ID(N'dbo.problem_feedback')
)
BEGIN
    CREATE INDEX idx_problem_feedback_user_created_at
    ON dbo.problem_feedback (user_id, created_at DESC);
END;
