abstract final class Schema {
  static const version = 2;

  static const migration1 = <String>[
    '''CREATE TABLE payment_sources (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      status TEXT NOT NULL
    )''',
    '''CREATE TABLE merchants (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL
    )''',
    '''CREATE TABLE categories (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      origin TEXT NOT NULL
    )''',
    '''CREATE TABLE tags (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL
    )''',
    '''CREATE TABLE provenances (
      id TEXT PRIMARY KEY NOT NULL,
      source_type TEXT NOT NULL,
      captured_at TEXT NOT NULL,
      source_id TEXT,
      original_representation TEXT,
      source_language TEXT
    )''',
    '''CREATE TABLE transactions (
      id TEXT PRIMARY KEY NOT NULL,
      occurred_at TEXT,
      unknown_time_reason TEXT,
      amount_coefficient TEXT NOT NULL,
      amount_scale INTEGER NOT NULL CHECK(amount_scale >= 0),
      currency TEXT NOT NULL,
      direction TEXT NOT NULL,
      source_type TEXT NOT NULL,
      status TEXT NOT NULL,
      description TEXT,
      raw_counterparty TEXT,
      source_language TEXT,
      notes TEXT,
      payment_source_id TEXT REFERENCES payment_sources(id),
      merchant_id TEXT REFERENCES merchants(id),
      category_id TEXT REFERENCES categories(id),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK ((occurred_at IS NOT NULL) != (unknown_time_reason IS NOT NULL))
    )''',
    '''CREATE TABLE transaction_provenances (
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      provenance_id TEXT NOT NULL REFERENCES provenances(id),
      PRIMARY KEY(transaction_id, provenance_id)
    )''',
    '''CREATE TABLE transaction_tags (
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      tag_id TEXT NOT NULL REFERENCES tags(id),
      PRIMARY KEY(transaction_id, tag_id)
    )''',
    '''CREATE TABLE review_issues (
      id TEXT PRIMARY KEY NOT NULL,
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      reason TEXT NOT NULL,
      status TEXT NOT NULL,
      detail TEXT,
      created_at TEXT NOT NULL,
      closed_at TEXT
    )''',
    '''CREATE TABLE exchange_rates (
      id TEXT PRIMARY KEY NOT NULL,
      from_currency TEXT NOT NULL,
      to_currency TEXT NOT NULL,
      rate_coefficient TEXT NOT NULL,
      rate_scale INTEGER NOT NULL CHECK(rate_scale >= 0),
      effective_at TEXT NOT NULL,
      source TEXT NOT NULL
    )''',
    '''CREATE TABLE normalized_money (
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      exchange_rate_id TEXT NOT NULL REFERENCES exchange_rates(id),
      amount_coefficient TEXT NOT NULL,
      amount_scale INTEGER NOT NULL CHECK(amount_scale >= 0),
      currency TEXT NOT NULL,
      PRIMARY KEY(transaction_id, exchange_rate_id)
    )''',
    '''CREATE TABLE evidence_items (
      id TEXT PRIMARY KEY NOT NULL,
      type TEXT NOT NULL,
      original_name TEXT NOT NULL,
      media_type TEXT NOT NULL,
      provenance_id TEXT NOT NULL REFERENCES provenances(id),
      created_at TEXT NOT NULL,
      source_language TEXT
    )''',
    '''CREATE TABLE extractions (
      id TEXT PRIMARY KEY NOT NULL,
      evidence_id TEXT NOT NULL REFERENCES evidence_items(id) ON DELETE CASCADE,
      values_json TEXT NOT NULL,
      provenance_id TEXT NOT NULL REFERENCES provenances(id),
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE attachment_links (
      id TEXT PRIMARY KEY NOT NULL,
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      evidence_id TEXT NOT NULL REFERENCES evidence_items(id),
      created_at TEXT NOT NULL,
      UNIQUE(transaction_id, evidence_id)
    )''',
    '''CREATE TABLE suggestions (
      id TEXT PRIMARY KEY NOT NULL,
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      target TEXT NOT NULL,
      proposed_value TEXT NOT NULL,
      method TEXT NOT NULL,
      status TEXT NOT NULL,
      provenance_id TEXT NOT NULL REFERENCES provenances(id),
      created_at TEXT NOT NULL,
      decided_at TEXT,
      confidence REAL CHECK(confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
      rationale TEXT,
      provider TEXT,
      model TEXT
    )''',
    'CREATE INDEX idx_transactions_occurred_at ON transactions(occurred_at)',
    'CREATE INDEX idx_transactions_merchant ON transactions(merchant_id)',
    'CREATE INDEX idx_transactions_category ON transactions(category_id)',
    'CREATE INDEX idx_review_issues_active ON review_issues(transaction_id, status)',
    'CREATE INDEX idx_attachment_links_transaction ON attachment_links(transaction_id)',
  ];

  static const migration2 = <String>[
    'ALTER TABLE transactions ADD COLUMN transaction_date TEXT',
    'ALTER TABLE transactions ADD COLUMN occurred_at_utc TEXT',
    'ALTER TABLE transactions ADD COLUMN time_zone_id TEXT',
    "UPDATE transactions SET occurred_at_utc = occurred_at WHERE occurred_at IS NOT NULL",
    "UPDATE transactions SET transaction_date = substr(occurred_at, 1, 10) WHERE occurred_at IS NOT NULL",
    'CREATE INDEX idx_transactions_transaction_date ON transactions(transaction_date)',
  ];
}
