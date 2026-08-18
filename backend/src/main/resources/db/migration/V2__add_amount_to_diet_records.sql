ALTER TABLE diet_records
    ADD COLUMN IF NOT EXISTS amount INTEGER;

UPDATE diet_records
SET amount = 1
WHERE amount IS NULL;

ALTER TABLE diet_records
    ALTER COLUMN amount SET DEFAULT 1;

ALTER TABLE diet_records
    ALTER COLUMN amount SET NOT NULL;
