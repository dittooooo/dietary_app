IF COL_LENGTH('dbo.users', 'enabled') IS NULL
BEGIN
    ALTER TABLE dbo.users ADD enabled BIT NULL;
END;

EXEC(N'
    UPDATE dbo.users
    SET enabled = 1
    WHERE enabled IS NULL
');

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.users')
      AND c.name = 'enabled'
)
BEGIN
    EXEC(N'ALTER TABLE dbo.users ADD CONSTRAINT DF_users_enabled DEFAULT 1 FOR enabled');
END;

EXEC(N'ALTER TABLE dbo.users ALTER COLUMN enabled BIT NOT NULL');
