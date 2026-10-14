CREATE TABLE IF NOT EXISTS restore_commits (
  operation_id TEXT PRIMARY KEY NOT NULL,
  committed_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS restore_context (
  id INTEGER PRIMARY KEY NOT NULL CHECK(id = 1),
  backup_time TEXT NOT NULL
);

ALTER TABLE duplicate_candidate_group_transactions
  ADD COLUMN created_at TEXT NOT NULL DEFAULT '';
ALTER TABLE transaction_provenances
  ADD COLUMN created_at TEXT NOT NULL DEFAULT '';

UPDATE duplicate_candidate_group_transactions
SET created_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE created_at = '';
UPDATE transaction_provenances
SET created_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE created_at = '';

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

CREATE TRIGGER IF NOT EXISTS duplicate_membership_merge_insert AFTER INSERT ON duplicate_candidate_group_transactions
BEGIN
  UPDATE duplicate_candidate_group_transactions
  SET created_at = CASE
    WHEN NEW.created_at = '' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now')
    ELSE NEW.created_at
  END
  WHERE group_id = NEW.group_id AND transaction_id = NEW.transaction_id;
  DELETE FROM entity_tombstones
  WHERE entity_type = 'duplicate_candidate_group_transactions'
    AND entity_id = NEW.group_id || '|' || NEW.transaction_id;
END;
CREATE TRIGGER IF NOT EXISTS duplicate_membership_preserve_newer_delete BEFORE DELETE ON duplicate_candidate_group_transactions
WHEN EXISTS (
  SELECT 1 FROM restore_context
  WHERE id = 1 AND OLD.created_at > backup_time
)
BEGIN
  SELECT RAISE(IGNORE);
END;
CREATE TRIGGER IF NOT EXISTS duplicate_membership_preserve_newer_update BEFORE UPDATE ON duplicate_candidate_group_transactions
WHEN EXISTS (
  SELECT 1 FROM restore_context
  WHERE id = 1 AND OLD.created_at > backup_time
)
BEGIN
  SELECT RAISE(IGNORE);
END;
CREATE TRIGGER IF NOT EXISTS duplicate_membership_tombstone AFTER DELETE ON duplicate_candidate_group_transactions
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('duplicate_candidate_group_transactions', OLD.group_id || '|' || OLD.transaction_id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;

CREATE TRIGGER IF NOT EXISTS transaction_provenance_merge_insert AFTER INSERT ON transaction_provenances
BEGIN
  UPDATE transaction_provenances
  SET created_at = CASE
    WHEN NEW.created_at = '' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now')
    ELSE NEW.created_at
  END
  WHERE transaction_id = NEW.transaction_id AND provenance_id = NEW.provenance_id;
  DELETE FROM entity_tombstones
  WHERE entity_type = 'transaction_provenances'
    AND entity_id = NEW.transaction_id || '|' || NEW.provenance_id;
END;
CREATE TRIGGER IF NOT EXISTS transaction_provenance_preserve_newer_delete BEFORE DELETE ON transaction_provenances
WHEN EXISTS (
  SELECT 1 FROM restore_context
  WHERE id = 1 AND OLD.created_at > backup_time
)
BEGIN
  SELECT RAISE(IGNORE);
END;
CREATE TRIGGER IF NOT EXISTS transaction_provenance_preserve_newer_update BEFORE UPDATE ON transaction_provenances
WHEN EXISTS (
  SELECT 1 FROM restore_context
  WHERE id = 1 AND OLD.created_at > backup_time
)
BEGIN
  SELECT RAISE(IGNORE);
END;
CREATE TRIGGER IF NOT EXISTS transaction_provenance_tombstone AFTER DELETE ON transaction_provenances
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('transaction_provenances', OLD.transaction_id || '|' || OLD.provenance_id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;

CREATE TRIGGER IF NOT EXISTS preserve_newer_relationship_tombstone BEFORE INSERT ON entity_tombstones
WHEN EXISTS (
  SELECT 1 FROM restore_context rc
  WHERE rc.id = 1 AND (
    (NEW.entity_type = 'duplicate_candidate_group_transactions' AND EXISTS (
      SELECT 1 FROM duplicate_candidate_group_transactions d
      WHERE NEW.entity_id = d.group_id || '|' || d.transaction_id
        AND d.created_at > rc.backup_time
    )) OR
    (NEW.entity_type = 'transaction_provenances' AND EXISTS (
      SELECT 1 FROM transaction_provenances tp
      WHERE NEW.entity_id = tp.transaction_id || '|' || tp.provenance_id
        AND tp.created_at > rc.backup_time
    ))
  )
)
BEGIN
  SELECT RAISE(IGNORE);
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

-- Normal repository writes advance modification timestamps. Restore is the
-- exception: historical timestamps from the backup are merge metadata and must
-- be preserved exactly, so replace the v8 auto-touch triggers with guarded
-- variants that are disabled while restore_context is active.
DROP TRIGGER IF EXISTS payment_sources_merge_update;
CREATE TRIGGER payment_sources_merge_update AFTER UPDATE ON payment_sources
WHEN NEW.updated_at = OLD.updated_at
  AND NOT EXISTS (SELECT 1 FROM restore_context WHERE id = 1)
BEGIN
  UPDATE payment_sources
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

DROP TRIGGER IF EXISTS merchants_merge_update;
CREATE TRIGGER merchants_merge_update AFTER UPDATE ON merchants
WHEN NEW.updated_at = OLD.updated_at
  AND NOT EXISTS (SELECT 1 FROM restore_context WHERE id = 1)
BEGIN
  UPDATE merchants
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

DROP TRIGGER IF EXISTS categories_merge_update;
CREATE TRIGGER categories_merge_update AFTER UPDATE ON categories
WHEN NEW.updated_at = OLD.updated_at
  AND NOT EXISTS (SELECT 1 FROM restore_context WHERE id = 1)
BEGIN
  UPDATE categories
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

DROP TRIGGER IF EXISTS tags_merge_update;
CREATE TRIGGER tags_merge_update AFTER UPDATE ON tags
WHEN NEW.updated_at = OLD.updated_at
  AND NOT EXISTS (SELECT 1 FROM restore_context WHERE id = 1)
BEGIN
  UPDATE tags
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

DROP TRIGGER IF EXISTS user_preferences_merge_update;
CREATE TRIGGER user_preferences_merge_update AFTER UPDATE ON user_preferences
WHEN NEW.updated_at = OLD.updated_at
  AND NOT EXISTS (SELECT 1 FROM restore_context WHERE id = 1)
BEGIN
  UPDATE user_preferences
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

-- Merge must not create new user deletion metadata merely because restore is
-- replaying a backup deletion. Generated tombstone timestamps are necessarily
-- later than the backup boundary, so ignore them while restore_context is
-- active. Backup tombstones themselves are at or before the backup boundary.
CREATE TRIGGER IF NOT EXISTS suppress_restore_generated_tombstone
BEFORE INSERT ON entity_tombstones
WHEN EXISTS (
  SELECT 1 FROM restore_context rc
  WHERE rc.id = 1 AND NEW.deleted_at > rc.backup_time
)
BEGIN
  SELECT RAISE(IGNORE);
END;

-- If the local workspace already carries a deletion newer than the backup
-- boundary, that deletion wins. Never let an older backup tombstone replace its
-- timestamp, otherwise a later restore could resurrect an entity that was
-- deleted locally after this backup was created.
CREATE TRIGGER IF NOT EXISTS preserve_newer_local_tombstone
BEFORE INSERT ON entity_tombstones
WHEN EXISTS (
  SELECT 1
  FROM restore_context rc
  JOIN entity_tombstones current
    ON current.entity_type = NEW.entity_type
   AND current.entity_id = NEW.entity_id
  WHERE rc.id = 1 AND current.deleted_at > rc.backup_time
)
BEGIN
  SELECT RAISE(IGNORE);
END;