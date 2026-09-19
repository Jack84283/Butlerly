CREATE TABLE classification_rules (
  id TEXT PRIMARY KEY NOT NULL,
  pattern TEXT NOT NULL,
  match_mode TEXT NOT NULL CHECK(match_mode IN ('exact', 'prefix')),
  enabled INTEGER NOT NULL CHECK(enabled IN (0, 1)),
  merchant_id TEXT REFERENCES merchants(id),
  category_id TEXT REFERENCES categories(id),
  subcategory_id TEXT REFERENCES categories(id),
  tag_ids_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK (merchant_id IS NOT NULL OR category_id IS NOT NULL OR subcategory_id IS NOT NULL OR tag_ids_json != '[]'),
  CHECK (subcategory_id IS NULL OR category_id IS NOT NULL)
);

CREATE INDEX idx_classification_rules_enabled_pattern
  ON classification_rules(enabled, pattern);
