IF COL_LENGTH('dbo.diet_records', 'amount') IS NULL
BEGIN
    ALTER TABLE dbo.diet_records ADD amount INT NULL;
END;
GO

UPDATE dbo.diet_records
SET amount = 1
WHERE amount IS NULL;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints dc
    INNER JOIN sys.columns c ON c.default_object_id = dc.object_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.diet_records')
      AND c.name = 'amount'
)
BEGIN
    ALTER TABLE dbo.diet_records ADD CONSTRAINT DF_diet_records_amount DEFAULT 1 FOR amount;
END;
GO

ALTER TABLE dbo.diet_records ALTER COLUMN amount INT NOT NULL;
