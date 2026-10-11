ALTER TABLE duplicate_candidate_groups
ADD COLUMN statement_rows TEXT NOT NULL DEFAULT '[]';
