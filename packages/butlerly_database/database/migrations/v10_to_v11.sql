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
