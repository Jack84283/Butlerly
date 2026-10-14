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
