ALTER TABLE problem_feedback
    ADD COLUMN IF NOT EXISTS admin_reply TEXT,
    ADD COLUMN IF NOT EXISTS replied_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_problem_feedback_created_at
ON problem_feedback (created_at DESC);
