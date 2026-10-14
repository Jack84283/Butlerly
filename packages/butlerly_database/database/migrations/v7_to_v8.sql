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
