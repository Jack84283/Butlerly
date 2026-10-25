-- Butlerly SQLite upgrade deployment, schema targets 2 through 14.
-- Each block is run ONLY when upgrading to that target version, in order.
-- Never run this whole file using sqlite3 .read against an existing database.
-- Fresh installations use database/schema/v1.sql plus the marked hardening block.
-- Retain existing data migrations, including their data rewrites and cleanup.

-- BUTLERLY_MIGRATION_TARGET: 2
-- Source: v1_to_v2.sql
-- Persist the row status that preceded a skip disposition.
ALTER TABLE statement_rows ADD COLUMN status_before_skip TEXT;

-- BUTLERLY_MIGRATION_TARGET: 3
-- Source: v2_to_v3.sql
CREATE TABLE IF NOT EXISTS analysis_rule_results (
      id TEXT PRIMARY KEY NOT NULL,
      rule_id TEXT NOT NULL,
      rule_version TEXT NOT NULL,
      definition_hash TEXT NOT NULL,
      result_type TEXT NOT NULL,
      surface TEXT NOT NULL,
      period_start TEXT NOT NULL,
      period_end TEXT NOT NULL,
      time_zone_id TEXT NOT NULL,
      dataset_mode TEXT NOT NULL,
      currency_basis TEXT NOT NULL,
      base_currency TEXT,
      dimension TEXT,
      result_set_key TEXT,
      result_set_size INTEGER NOT NULL DEFAULT 1,
      payload TEXT NOT NULL,
      calculated_at TEXT NOT NULL,
      source_revision INTEGER NOT NULL,
      freshness TEXT NOT NULL DEFAULT 'fresh',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK (freshness IN ('fresh', 'stale'))
    );

CREATE INDEX IF NOT EXISTS idx_analysis_rule_results_lookup
  ON analysis_rule_results(rule_id, rule_version, definition_hash,
                           period_start, period_end, time_zone_id,
                           dataset_mode, currency_basis, base_currency,
                           dimension, freshness);

-- BUTLERLY_MIGRATION_TARGET: 4
-- Source: v3_to_v4.sql
ALTER TABLE merchants ADD COLUMN normalized_name TEXT NOT NULL DEFAULT '';
ALTER TABLE merchants ADD COLUMN default_category_id TEXT REFERENCES categories(id);
ALTER TABLE merchants ADD COLUMN default_subcategory_id TEXT REFERENCES categories(id);
ALTER TABLE merchants ADD COLUMN is_built_in INTEGER NOT NULL DEFAULT 0;

UPDATE merchants
SET normalized_name = lower(trim(name))
WHERE normalized_name = '';

-- BUTLERLY_MIGRATION_TARGET: 5
-- Source: v4_to_v5.sql
ALTER TABLE transactions ADD COLUMN subcategory_id TEXT REFERENCES categories(id);
ALTER TABLE transactions ADD COLUMN normalized_description TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_transactions_classification_merchant
  ON transactions(merchant_id, status, category_id, subcategory_id);
CREATE INDEX IF NOT EXISTS idx_transactions_classification_description
  ON transactions(normalized_description, status, category_id, subcategory_id);

-- BUTLERLY_MIGRATION_TARGET: 6
-- Source: v5_to_v6.sql
ALTER TABLE statement_rows ADD COLUMN subcategory_id TEXT REFERENCES categories(id);

UPDATE statement_rows
SET
  subcategory_id = category_id,
  category_id = (
    SELECT parent_id
    FROM categories
    WHERE categories.id = statement_rows.category_id
  )
WHERE subcategory_id IS NULL
  AND category_id IN (
    SELECT id
    FROM categories
    WHERE parent_id IS NOT NULL
  );

-- BUTLERLY_MIGRATION_TARGET: 7
-- Source: v6_to_v7.sql
ALTER TABLE analysis_rule_results
  ADD COLUMN period_type TEXT NOT NULL DEFAULT 'selected_period';

-- BUTLERLY_MIGRATION_TARGET: 8
-- Source: v7_to_v8.sql
CREATE TABLE entity_tombstones (
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  deleted_at TEXT NOT NULL,
  PRIMARY KEY(entity_type, entity_id)
);
CREATE INDEX idx_entity_tombstones_deleted_at ON entity_tombstones(deleted_at);

ALTER TABLE payment_sources ADD COLUMN created_at TEXT NOT NULL DEFAULT '';
ALTER TABLE payment_sources ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
ALTER TABLE merchants ADD COLUMN created_at TEXT NOT NULL DEFAULT '';
ALTER TABLE merchants ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
ALTER TABLE categories ADD COLUMN created_at TEXT NOT NULL DEFAULT '';
ALTER TABLE categories ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
ALTER TABLE tags ADD COLUMN created_at TEXT NOT NULL DEFAULT '';
ALTER TABLE tags ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
ALTER TABLE transaction_tags ADD COLUMN created_at TEXT NOT NULL DEFAULT '';
ALTER TABLE user_preferences ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';

UPDATE payment_sources
SET created_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE created_at = '' OR updated_at = '';
UPDATE merchants
SET created_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE created_at = '' OR updated_at = '';
UPDATE categories
SET created_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE created_at = '' OR updated_at = '';
UPDATE tags
SET created_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE created_at = '' OR updated_at = '';
UPDATE transaction_tags
SET created_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE created_at = '';
UPDATE user_preferences
SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE updated_at = '';

CREATE TRIGGER payment_sources_merge_insert AFTER INSERT ON payment_sources
WHEN NEW.created_at = '' OR NEW.updated_at = ''
BEGIN
  UPDATE payment_sources
  SET created_at = CASE WHEN NEW.created_at = '' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now') ELSE NEW.created_at END,
      updated_at = CASE WHEN NEW.updated_at = '' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now') ELSE NEW.updated_at END
  WHERE id = NEW.id;
END;
CREATE TRIGGER payment_sources_merge_update AFTER UPDATE ON payment_sources
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE payment_sources
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

CREATE TRIGGER merchants_merge_insert AFTER INSERT ON merchants
WHEN NEW.created_at = '' OR NEW.updated_at = ''
BEGIN
  UPDATE merchants
  SET created_at = CASE WHEN NEW.created_at = '' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now') ELSE NEW.created_at END,
      updated_at = CASE WHEN NEW.updated_at = '' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now') ELSE NEW.updated_at END
  WHERE id = NEW.id;
END;
CREATE TRIGGER merchants_merge_update AFTER UPDATE ON merchants
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE merchants
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

CREATE TRIGGER categories_merge_insert AFTER INSERT ON categories
WHEN NEW.created_at = '' OR NEW.updated_at = ''
BEGIN
  UPDATE categories
  SET created_at = CASE WHEN NEW.created_at = '' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now') ELSE NEW.created_at END,
      updated_at = CASE WHEN NEW.updated_at = '' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now') ELSE NEW.updated_at END
  WHERE id = NEW.id;
END;
CREATE TRIGGER categories_merge_update AFTER UPDATE ON categories
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE categories
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

CREATE TRIGGER tags_merge_insert AFTER INSERT ON tags
WHEN NEW.created_at = '' OR NEW.updated_at = ''
BEGIN
  UPDATE tags
  SET created_at = CASE WHEN NEW.created_at = '' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now') ELSE NEW.created_at END,
      updated_at = CASE WHEN NEW.updated_at = '' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now') ELSE NEW.updated_at END
  WHERE id = NEW.id;
END;
CREATE TRIGGER tags_merge_update AFTER UPDATE ON tags
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE tags
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

CREATE TRIGGER transaction_tags_merge_insert AFTER INSERT ON transaction_tags
BEGIN
  UPDATE transaction_tags
  SET created_at = CASE WHEN NEW.created_at = '' THEN strftime('%Y-%m-%dT%H:%M:%fZ','now') ELSE NEW.created_at END
  WHERE transaction_id = NEW.transaction_id AND tag_id = NEW.tag_id;
  DELETE FROM entity_tombstones
  WHERE entity_type = 'transaction_tags'
    AND entity_id = NEW.transaction_id || '|' || NEW.tag_id;
END;

CREATE TRIGGER user_preferences_merge_update AFTER UPDATE ON user_preferences
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE user_preferences
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

CREATE TRIGGER transactions_tombstone AFTER DELETE ON transactions
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('transactions', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER transactions_tombstone_clear AFTER INSERT ON transactions
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'transactions' AND entity_id = NEW.id;
END;

CREATE TRIGGER payment_sources_tombstone AFTER DELETE ON payment_sources
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('payment_sources', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER payment_sources_tombstone_clear AFTER INSERT ON payment_sources
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'payment_sources' AND entity_id = NEW.id;
END;

CREATE TRIGGER merchants_tombstone AFTER DELETE ON merchants
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('merchants', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER merchants_tombstone_clear AFTER INSERT ON merchants
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'merchants' AND entity_id = NEW.id;
END;

CREATE TRIGGER categories_tombstone AFTER DELETE ON categories
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('categories', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER categories_tombstone_clear AFTER INSERT ON categories
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'categories' AND entity_id = NEW.id;
END;

CREATE TRIGGER tags_tombstone AFTER DELETE ON tags
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('tags', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER tags_tombstone_clear AFTER INSERT ON tags
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'tags' AND entity_id = NEW.id;
END;

CREATE TRIGGER transaction_tags_tombstone AFTER DELETE ON transaction_tags
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('transaction_tags', OLD.transaction_id || '|' || OLD.tag_id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;

CREATE TRIGGER evidence_items_tombstone AFTER DELETE ON evidence_items
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('evidence_items', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER evidence_items_tombstone_clear AFTER INSERT ON evidence_items
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'evidence_items' AND entity_id = NEW.id;
END;

CREATE TRIGGER attachment_links_tombstone AFTER DELETE ON attachment_links
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('attachment_links', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER attachment_links_tombstone_clear AFTER INSERT ON attachment_links
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'attachment_links' AND entity_id = NEW.id;
END;

CREATE TRIGGER reconciliation_links_tombstone AFTER DELETE ON reconciliation_links
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('reconciliation_links', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;
CREATE TRIGGER reconciliation_links_tombstone_clear AFTER INSERT ON reconciliation_links
BEGIN
  DELETE FROM entity_tombstones WHERE entity_type = 'reconciliation_links' AND entity_id = NEW.id;
END;

-- BUTLERLY_BASELINE_HARDENING_BEGIN
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
-- BUTLERLY_BASELINE_HARDENING_END

-- BUTLERLY_MIGRATION_TARGET: 9
-- Source: v8_to_v9.sql
CREATE TABLE payment_settlements (
  id TEXT PRIMARY KEY NOT NULL,
  settlement_transaction_id TEXT NOT NULL UNIQUE REFERENCES transactions(id) ON DELETE CASCADE,
  payment_source_id TEXT NOT NULL REFERENCES payment_sources(id),
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  statement_balance_coefficient TEXT,
  statement_balance_scale INTEGER CHECK(statement_balance_scale IS NULL OR statement_balance_scale >= 0),
  statement_balance_currency TEXT,
  status TEXT NOT NULL,
  description TEXT,
  external_reference TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK(period_end >= period_start),
  CHECK(
    (statement_balance_coefficient IS NULL) =
    (statement_balance_scale IS NULL)
    AND
    (statement_balance_scale IS NULL) =
    (statement_balance_currency IS NULL)
  )
);

CREATE INDEX payment_settlements_payment_source_period_idx
  ON payment_settlements(payment_source_id, period_start, period_end);

CREATE INDEX transactions_payment_source_date_idx
  ON transactions(payment_source_id, transaction_date);

CREATE TRIGGER payment_settlements_tombstone AFTER DELETE ON payment_settlements
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('payment_settlements', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;

CREATE TRIGGER payment_settlements_tombstone_clear AFTER INSERT ON payment_settlements
BEGIN
  DELETE FROM entity_tombstones
  WHERE entity_type = 'payment_settlements' AND entity_id = NEW.id;
END;

CREATE TRIGGER payment_settlements_validate_insert
BEFORE INSERT ON payment_settlements
WHEN NOT EXISTS (
  SELECT 1
  FROM transactions t
  WHERE t.id = NEW.settlement_transaction_id
    AND t.direction = 'transfer'
    AND t.status = 'active'
    AND t.payment_source_id = NEW.payment_source_id
    AND t.transaction_date IS NOT NULL
    AND (
      NEW.statement_balance_currency IS NULL
      OR t.currency = NEW.statement_balance_currency
    )
)
BEGIN
  SELECT RAISE(
    ABORT,
    'invalid payment settlement transaction relationship'
  );
END;

CREATE TRIGGER payment_settlements_validate_update
BEFORE UPDATE OF settlement_transaction_id, payment_source_id,
  statement_balance_currency ON payment_settlements
WHEN NOT EXISTS (
  SELECT 1
  FROM transactions t
  WHERE t.id = NEW.settlement_transaction_id
    AND t.direction = 'transfer'
    AND t.status = 'active'
    AND t.payment_source_id = NEW.payment_source_id
    AND t.transaction_date IS NOT NULL
    AND (
      NEW.statement_balance_currency IS NULL
      OR t.currency = NEW.statement_balance_currency
    )
)
BEGIN
  SELECT RAISE(
    ABORT,
    'invalid payment settlement transaction relationship'
  );
END;

CREATE TRIGGER settlement_payment_transaction_validate_update
BEFORE UPDATE OF direction, status, payment_source_id, transaction_date,
  currency ON transactions
WHEN EXISTS (
  SELECT 1
  FROM payment_settlements ps
  WHERE ps.settlement_transaction_id = OLD.id
)
AND (
  NEW.direction != 'transfer'
  OR NEW.status != 'active'
  OR NEW.transaction_date IS NULL
  OR EXISTS (
    SELECT 1
    FROM payment_settlements ps
    WHERE ps.settlement_transaction_id = OLD.id
      AND (
        NEW.payment_source_id IS NULL
        OR NEW.payment_source_id != ps.payment_source_id
        OR (
          ps.statement_balance_currency IS NOT NULL
          AND NEW.currency != ps.statement_balance_currency
        )
      )
  )
)
BEGIN
  SELECT RAISE(
    ABORT,
    'invalid settlement payment transaction update'
  );
END;

CREATE TRIGGER settlement_payment_transaction_review_update
AFTER UPDATE OF amount_coefficient, amount_scale, currency, transaction_date
ON transactions
WHEN (
  OLD.amount_coefficient != NEW.amount_coefficient
  OR OLD.amount_scale != NEW.amount_scale
  OR OLD.currency != NEW.currency
  OR OLD.transaction_date != NEW.transaction_date
)
AND NOT EXISTS (SELECT 1 FROM restore_context WHERE id = 1)
BEGIN
  UPDATE payment_settlements
  SET status = 'needsReview',
      updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE settlement_transaction_id = NEW.id
    AND status != 'needsReview';
END;

-- BUTLERLY_MIGRATION_TARGET: 10
-- Source: v9_to_v10.sql
CREATE TEMP TABLE settlement_payment_transaction_ids AS
SELECT settlement_transaction_id AS id
FROM payment_settlements;

DROP TRIGGER IF EXISTS payment_settlements_validate_insert;
DROP TRIGGER IF EXISTS payment_settlements_validate_update;
DROP TRIGGER IF EXISTS settlement_payment_transaction_validate_update;
DROP TRIGGER IF EXISTS settlement_payment_transaction_review_update;
DROP TRIGGER IF EXISTS payment_settlements_tombstone;
DROP TRIGGER IF EXISTS payment_settlements_tombstone_clear;

ALTER TABLE payment_settlements RENAME TO payment_settlements_v9;

CREATE TABLE payment_settlements (
  id TEXT PRIMARY KEY NOT NULL,
  payment_source_id TEXT NOT NULL REFERENCES payment_sources(id),
  payment_amount_coefficient TEXT NOT NULL,
  payment_amount_scale INTEGER NOT NULL CHECK(payment_amount_scale >= 0),
  payment_currency TEXT NOT NULL,
  payment_date TEXT NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  statement_balance_coefficient TEXT,
  statement_balance_scale INTEGER CHECK(statement_balance_scale IS NULL OR statement_balance_scale >= 0),
  statement_balance_currency TEXT,
  status TEXT NOT NULL,
  description TEXT,
  external_reference TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK(period_end >= period_start),
  CHECK(
    (statement_balance_coefficient IS NULL) =
    (statement_balance_scale IS NULL)
    AND
    (statement_balance_scale IS NULL) =
    (statement_balance_currency IS NULL)
  ),
  CHECK(
    statement_balance_currency IS NULL
    OR statement_balance_currency = payment_currency
  )
);

INSERT INTO payment_settlements (
  id,
  payment_source_id,
  payment_amount_coefficient,
  payment_amount_scale,
  payment_currency,
  payment_date,
  period_start,
  period_end,
  statement_balance_coefficient,
  statement_balance_scale,
  statement_balance_currency,
  status,
  description,
  external_reference,
  created_at,
  updated_at
)
SELECT
  ps.id,
  ps.payment_source_id,
  t.amount_coefficient,
  t.amount_scale,
  t.currency,
  t.transaction_date,
  ps.period_start,
  ps.period_end,
  ps.statement_balance_coefficient,
  ps.statement_balance_scale,
  ps.statement_balance_currency,
  ps.status,
  COALESCE(ps.description, t.description),
  COALESCE(ps.external_reference, t.external_reference),
  ps.created_at,
  ps.updated_at
FROM payment_settlements_v9 ps
JOIN transactions t ON t.id = ps.settlement_transaction_id;

DROP TABLE payment_settlements_v9;

UPDATE statement_rows
SET transaction_id = NULL
WHERE transaction_id IN (SELECT id FROM settlement_payment_transaction_ids);

CREATE TEMP TABLE settlement_duplicate_group_ids AS
SELECT DISTINCT group_id AS id
FROM duplicate_candidate_group_transactions
WHERE transaction_id IN (
  SELECT id FROM settlement_payment_transaction_ids
);

DELETE FROM duplicate_candidate_groups
WHERE id IN (SELECT id FROM settlement_duplicate_group_ids);

DELETE FROM reconciliation_links
WHERE receipt_transaction_id IN (
    SELECT id FROM settlement_payment_transaction_ids
  )
  OR payment_transaction_id IN (
    SELECT id FROM settlement_payment_transaction_ids
  )
  OR candidate_id IN (
    SELECT id
    FROM reconciliation_candidates
    WHERE receipt_transaction_id IN (
        SELECT id FROM settlement_payment_transaction_ids
      )
      OR payment_transaction_id IN (
        SELECT id FROM settlement_payment_transaction_ids
      )
  );

DELETE FROM reconciliation_candidates
WHERE receipt_transaction_id IN (
    SELECT id FROM settlement_payment_transaction_ids
  )
  OR payment_transaction_id IN (
    SELECT id FROM settlement_payment_transaction_ids
  );

DELETE FROM transactions
WHERE id IN (SELECT id FROM settlement_payment_transaction_ids);

DELETE FROM entity_tombstones
WHERE entity_type = 'transactions'
  AND entity_id IN (SELECT id FROM settlement_payment_transaction_ids);

DROP TABLE settlement_duplicate_group_ids;
DROP TABLE settlement_payment_transaction_ids;

CREATE INDEX payment_settlements_payment_source_period_idx
  ON payment_settlements(payment_source_id, period_start, period_end);

CREATE INDEX payment_settlements_payment_date_idx
  ON payment_settlements(payment_date);

CREATE TRIGGER payment_settlements_tombstone AFTER DELETE ON payment_settlements
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('payment_settlements', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;

CREATE TRIGGER payment_settlements_tombstone_clear AFTER INSERT ON payment_settlements
BEGIN
  DELETE FROM entity_tombstones
  WHERE entity_type = 'payment_settlements' AND entity_id = NEW.id;
END;

-- BUTLERLY_MIGRATION_TARGET: 11
-- Source: v10_to_v11.sql
CREATE TABLE merchant_aliases (
      id TEXT PRIMARY KEY NOT NULL,
      merchant_id TEXT NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
      alias TEXT NOT NULL,
      normalized_alias TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(merchant_id, normalized_alias)
    );

CREATE TABLE merchant_normalization_patterns (
      id TEXT PRIMARY KEY NOT NULL,
      merchant_id TEXT NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
      pattern TEXT NOT NULL,
      normalized_pattern TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(merchant_id, normalized_pattern)
    );

CREATE TABLE transaction_rules (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      enabled INTEGER NOT NULL DEFAULT 1,
      priority INTEGER NOT NULL DEFAULT 0,
      merchant_id TEXT,
      category_id TEXT,
      payment_source_id TEXT,
      tag_id TEXT,
      description_contains TEXT,
      raw_counterparty_contains TEXT,
      assign_merchant_id TEXT,
      assign_category_id TEXT,
      assign_subcategory_id TEXT,
      assign_payment_source_id TEXT,
      assign_tag_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK (
        merchant_id IS NOT NULL OR category_id IS NOT NULL OR
        payment_source_id IS NOT NULL OR tag_id IS NOT NULL OR
        description_contains IS NOT NULL OR raw_counterparty_contains IS NOT NULL
      ),
      CHECK (
        assign_merchant_id IS NOT NULL OR assign_category_id IS NOT NULL OR
        assign_subcategory_id IS NOT NULL OR assign_payment_source_id IS NOT NULL OR
        assign_tag_id IS NOT NULL
      )
    );

CREATE INDEX idx_merchant_aliases_merchant
  ON merchant_aliases(merchant_id, status);

CREATE INDEX idx_merchant_patterns_merchant
  ON merchant_normalization_patterns(merchant_id, status);

CREATE INDEX idx_transaction_rules_priority
  ON transaction_rules(enabled, priority);

CREATE TRIGGER merchant_aliases_tombstone AFTER DELETE ON merchant_aliases
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('merchant_aliases', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id) DO UPDATE SET deleted_at = excluded.deleted_at;
END;

CREATE TRIGGER merchant_aliases_tombstone_clear AFTER INSERT ON merchant_aliases
BEGIN
  DELETE FROM entity_tombstones
  WHERE entity_type = 'merchant_aliases' AND entity_id = NEW.id;
END;

CREATE TRIGGER merchant_normalization_patterns_tombstone
AFTER DELETE ON merchant_normalization_patterns
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES(
    'merchant_normalization_patterns',
    OLD.id,
    strftime('%Y-%m-%dT%H:%M:%fZ','now')
  )
  ON CONFLICT(entity_type, entity_id) DO UPDATE SET deleted_at = excluded.deleted_at;
END;

CREATE TRIGGER merchant_normalization_patterns_tombstone_clear
AFTER INSERT ON merchant_normalization_patterns
BEGIN
  DELETE FROM entity_tombstones
  WHERE entity_type = 'merchant_normalization_patterns' AND entity_id = NEW.id;
END;

CREATE TRIGGER transaction_rules_tombstone AFTER DELETE ON transaction_rules
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('transaction_rules', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id) DO UPDATE SET deleted_at = excluded.deleted_at;
END;

CREATE TRIGGER transaction_rules_tombstone_clear AFTER INSERT ON transaction_rules
BEGIN
  DELETE FROM entity_tombstones
  WHERE entity_type = 'transaction_rules' AND entity_id = NEW.id;
END;

-- BUTLERLY_MIGRATION_TARGET: 12
-- Source: v11_to_v12.sql
-- Normalize persisted transaction instants. Prefer a valid occurred_at_utc
-- value, then a valid occurred_at value. If neither can be recovered, retain
-- the transaction with the existing unknown-time representation instead of
-- leaving a value that DateTime.parse() cannot hydrate.
UPDATE transactions
SET occurred_at = CASE
      WHEN julianday(occurred_at_utc) IS NOT NULL
        THEN strftime('%Y-%m-%dT%H:%M:%fZ', occurred_at_utc)
      WHEN julianday(occurred_at) IS NOT NULL
        THEN strftime('%Y-%m-%dT%H:%M:%fZ', occurred_at)
      ELSE NULL
    END,
    occurred_at_utc = CASE
      WHEN julianday(occurred_at_utc) IS NOT NULL
        THEN strftime('%Y-%m-%dT%H:%M:%fZ', occurred_at_utc)
      WHEN julianday(occurred_at) IS NOT NULL
        THEN strftime('%Y-%m-%dT%H:%M:%fZ', occurred_at)
      ELSE NULL
    END,
    unknown_time_reason = CASE
      WHEN julianday(occurred_at_utc) IS NOT NULL
        OR julianday(occurred_at) IS NOT NULL
        THEN NULL
      ELSE COALESCE(NULLIF(unknown_time_reason, ''), 'unknown')
    END
WHERE occurred_at IS NOT NULL OR occurred_at_utc IS NOT NULL;

-- BUTLERLY_MIGRATION_TARGET: 13
-- Source: v12_to_v13.sql
CREATE TABLE recurring_pattern_decisions (
      id TEXT PRIMARY KEY NOT NULL,
      pattern_key TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL CHECK(status IN ('confirmed', 'rejected', 'corrected')),
      cadence TEXT NOT NULL CHECK(cadence IN ('weekly', 'biweekly', 'monthly', 'quarterly', 'irregular')),
      interval_days INTEGER NOT NULL CHECK(interval_days > 0),
      expected_amount_coefficient TEXT NOT NULL,
      expected_amount_scale INTEGER NOT NULL CHECK(expected_amount_scale >= 0),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

CREATE INDEX idx_recurring_pattern_decisions_key
  ON recurring_pattern_decisions(pattern_key);

-- BUTLERLY_MIGRATION_TARGET: 14
-- Source: v13_to_v14.sql
ALTER TABLE duplicate_candidate_groups
ADD COLUMN statement_rows TEXT NOT NULL DEFAULT '[]';


-- BUTLERLY_MIGRATION_TARGET: 15
-- Source: v14_to_v15.sql
ALTER TABLE user_preferences ADD COLUMN display_name TEXT NOT NULL DEFAULT '';

-- BUTLERLY_MIGRATION_TARGET: 16
-- Source: v15_to_v16.sql
ALTER TABLE payment_sources ADD COLUMN network TEXT;

-- BUTLERLY_MIGRATION_TARGET: 17
-- Source: v16_to_v17.sql
ALTER TABLE user_preferences ADD COLUMN transaction_save_sound_enabled INTEGER NOT NULL DEFAULT 1 CHECK(transaction_save_sound_enabled IN (0, 1));

-- BUTLERLY_MIGRATION_TARGET: 18
-- Source: v17_to_v18.sql
CREATE TABLE IF NOT EXISTS budgets (
      id TEXT PRIMARY KEY NOT NULL,
      scope TEXT NOT NULL CHECK(scope IN ('overall', 'category', 'subcategory', 'merchant')),
      scope_id TEXT,
      currency TEXT NOT NULL,
      amount TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK ((scope = 'overall' AND scope_id IS NULL)
          OR (scope != 'overall' AND scope_id IS NOT NULL)),
      UNIQUE (scope, scope_id, currency)
    );
CREATE UNIQUE INDEX IF NOT EXISTS idx_budget_scope_currency
  ON budgets(scope, COALESCE(scope_id, ''), currency);
