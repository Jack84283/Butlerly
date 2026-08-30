-- Persist the row status that preceded a skip disposition.
ALTER TABLE statement_rows ADD COLUMN status_before_skip TEXT;
