CREATE TABLE IF NOT EXISTS restore_commits (
  operation_id TEXT PRIMARY KEY NOT NULL,
  committed_at TEXT NOT NULL
);

CREATE TRIGGER IF NOT EXISTS review_issues_tombstone AFTER DELETE ON review_issues
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('review_issues', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER IF NOT EXISTS review_issues_tombstone_clear AFTER INSERT ON review_issues
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'review_issues' AND entity_id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS duplicate_membership_tombstone AFTER DELETE ON duplicate_candidate_group_transactions
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('duplicate_candidate_group_transactions', OLD.group_id || '|' || OLD.transaction_id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER IF NOT EXISTS duplicate_membership_tombstone_clear AFTER INSERT ON duplicate_candidate_group_transactions
BEGIN
  DELETE FROM entity_tombstones
  WHERE entity_type = 'duplicate_candidate_group_transactions'
    AND entity_id = NEW.group_id || '|' || NEW.transaction_id;
END;

CREATE TRIGGER IF NOT EXISTS transaction_provenance_tombstone AFTER DELETE ON transaction_provenances
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('transaction_provenances', OLD.transaction_id || '|' || OLD.provenance_id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER IF NOT EXISTS transaction_provenance_tombstone_clear AFTER INSERT ON transaction_provenances
BEGIN
  DELETE FROM entity_tombstones
  WHERE entity_type = 'transaction_provenances'
    AND entity_id = NEW.transaction_id || '|' || NEW.provenance_id;
END;

CREATE TRIGGER IF NOT EXISTS suggestions_tombstone AFTER DELETE ON suggestions
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('suggestions', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER IF NOT EXISTS suggestions_tombstone_clear AFTER INSERT ON suggestions
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'suggestions' AND entity_id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS extractions_tombstone AFTER DELETE ON extractions
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('extractions', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER IF NOT EXISTS extractions_tombstone_clear AFTER INSERT ON extractions
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'extractions' AND entity_id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS reconciliation_candidates_tombstone AFTER DELETE ON reconciliation_candidates
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('reconciliation_candidates', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER IF NOT EXISTS reconciliation_candidates_tombstone_clear AFTER INSERT ON reconciliation_candidates
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'reconciliation_candidates' AND entity_id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS duplicate_groups_tombstone AFTER DELETE ON duplicate_candidate_groups
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('duplicate_candidate_groups', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER IF NOT EXISTS duplicate_groups_tombstone_clear AFTER INSERT ON duplicate_candidate_groups
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'duplicate_candidate_groups' AND entity_id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS statement_rows_tombstone AFTER DELETE ON statement_rows
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('statement_rows', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER IF NOT EXISTS statement_rows_tombstone_clear AFTER INSERT ON statement_rows
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'statement_rows' AND entity_id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS financial_statements_tombstone AFTER DELETE ON financial_statements
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('financial_statements', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER IF NOT EXISTS financial_statements_tombstone_clear AFTER INSERT ON financial_statements
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'financial_statements' AND entity_id = NEW.id;
END;
