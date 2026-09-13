ALTER TABLE payment_sources ADD COLUMN created_at TEXT NOT NULL DEFAULT '';
ALTER TABLE payment_sources ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
ALTER TABLE merchants ADD COLUMN created_at TEXT NOT NULL DEFAULT '';
ALTER TABLE merchants ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
ALTER TABLE categories ADD COLUMN created_at TEXT NOT NULL DEFAULT '';
ALTER TABLE categories ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
ALTER TABLE tags ADD COLUMN created_at TEXT NOT NULL DEFAULT '';
ALTER TABLE tags ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';
ALTER TABLE user_preferences ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';

UPDATE payment_sources SET created_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE created_at = '' OR updated_at = '';
UPDATE merchants SET created_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE created_at = '' OR updated_at = '';
UPDATE categories SET created_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE created_at = '' OR updated_at = '';
UPDATE tags SET created_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE created_at = '' OR updated_at = '';
UPDATE user_preferences SET updated_at = CURRENT_TIMESTAMP WHERE updated_at = '';

CREATE TRIGGER payment_sources_merge_insert AFTER INSERT ON payment_sources
WHEN NEW.created_at = '' OR NEW.updated_at = ''
BEGIN
  UPDATE payment_sources
  SET created_at = CASE WHEN NEW.created_at = '' THEN CURRENT_TIMESTAMP ELSE NEW.created_at END,
      updated_at = CASE WHEN NEW.updated_at = '' THEN CURRENT_TIMESTAMP ELSE NEW.updated_at END
  WHERE id = NEW.id;
END;
CREATE TRIGGER payment_sources_merge_update AFTER UPDATE ON payment_sources
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE payment_sources SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER merchants_merge_insert AFTER INSERT ON merchants
WHEN NEW.created_at = '' OR NEW.updated_at = ''
BEGIN
  UPDATE merchants
  SET created_at = CASE WHEN NEW.created_at = '' THEN CURRENT_TIMESTAMP ELSE NEW.created_at END,
      updated_at = CASE WHEN NEW.updated_at = '' THEN CURRENT_TIMESTAMP ELSE NEW.updated_at END
  WHERE id = NEW.id;
END;
CREATE TRIGGER merchants_merge_update AFTER UPDATE ON merchants
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE merchants SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER categories_merge_insert AFTER INSERT ON categories
WHEN NEW.created_at = '' OR NEW.updated_at = ''
BEGIN
  UPDATE categories
  SET created_at = CASE WHEN NEW.created_at = '' THEN CURRENT_TIMESTAMP ELSE NEW.created_at END,
      updated_at = CASE WHEN NEW.updated_at = '' THEN CURRENT_TIMESTAMP ELSE NEW.updated_at END
  WHERE id = NEW.id;
END;
CREATE TRIGGER categories_merge_update AFTER UPDATE ON categories
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE categories SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER tags_merge_insert AFTER INSERT ON tags
WHEN NEW.created_at = '' OR NEW.updated_at = ''
BEGIN
  UPDATE tags
  SET created_at = CASE WHEN NEW.created_at = '' THEN CURRENT_TIMESTAMP ELSE NEW.created_at END,
      updated_at = CASE WHEN NEW.updated_at = '' THEN CURRENT_TIMESTAMP ELSE NEW.updated_at END
  WHERE id = NEW.id;
END;
CREATE TRIGGER tags_merge_update AFTER UPDATE ON tags
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE tags SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER user_preferences_merge_update AFTER UPDATE ON user_preferences
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE user_preferences SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TABLE entity_tombstones (
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  deleted_at TEXT NOT NULL,
  PRIMARY KEY(entity_type, entity_id)
);
CREATE INDEX idx_entity_tombstones_deleted_at ON entity_tombstones(deleted_at);
