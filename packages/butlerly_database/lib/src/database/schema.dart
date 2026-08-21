abstract final class Schema {
  static const version = 10;

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
    'CREATE INDEX idx_transactions_transaction_date ON transactions(transaction_date)',
  ];

  static const migration3 = <String>[
    'ALTER TABLE categories ADD COLUMN parent_id TEXT REFERENCES categories(id)',
    'CREATE INDEX idx_categories_parent ON categories(parent_id)',
  ];

  static const migration4 = <String>[
    '''CREATE TABLE user_preferences (
      id INTEGER PRIMARY KEY NOT NULL CHECK(id = 1),
      locale TEXT NOT NULL,
      base_currency TEXT NOT NULL,
      time_zone_id TEXT NOT NULL,
      external_ai_enabled INTEGER NOT NULL CHECK(external_ai_enabled IN (0, 1))
    )''',
  ];

  static const migration5 = <String>[
    'ALTER TABLE user_preferences ADD COLUMN first_use_completed INTEGER NOT NULL DEFAULT 0 CHECK(first_use_completed IN (0, 1))',
  ];

  static const migration6 = <String>[
    'ALTER TABLE evidence_items ADD COLUMN local_file_name TEXT',
  ];

  static const migration7 = <String>[
    'ALTER TABLE payment_sources ADD COLUMN display_identity TEXT',
    'ALTER TABLE payment_sources ADD COLUMN last_four TEXT',
    'ALTER TABLE merchants ADD COLUMN status TEXT NOT NULL DEFAULT \'active\'',
    'ALTER TABLE merchants ADD COLUMN raw_name TEXT',
    'ALTER TABLE categories ADD COLUMN status TEXT NOT NULL DEFAULT \'active\'',
    'ALTER TABLE tags ADD COLUMN status TEXT NOT NULL DEFAULT \'active\'',
  ];

  static const migration8 = <String>[
    'ALTER TABLE transactions ADD COLUMN external_reference TEXT',
    'CREATE INDEX idx_transactions_external_reference ON transactions(external_reference)',
  ];

  static const migration9 = <String>[
    '''CREATE TABLE reconciliation_candidates (
      id TEXT PRIMARY KEY NOT NULL,
      receipt_transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      payment_transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      score REAL NOT NULL CHECK(score >= 0 AND score <= 1),
      reasons_json TEXT NOT NULL,
      status TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(receipt_transaction_id, payment_transaction_id)
    )''',
    'CREATE INDEX idx_reconciliation_candidates_status ON reconciliation_candidates(status)',
  ];

  static const migration10 = <String>[
    'ALTER TABLE payment_sources ADD COLUMN issuer TEXT',
    'ALTER TABLE payment_sources ADD COLUMN currency TEXT',
    'ALTER TABLE payment_sources ADD COLUMN note TEXT',
  ];
}
