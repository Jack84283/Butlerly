abstract final class Schema {
  static const version = 19;

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

  static const migration11 = <String>[
    '''CREATE TABLE reconciliation_links (
      id TEXT PRIMARY KEY NOT NULL,
      candidate_id TEXT NOT NULL UNIQUE REFERENCES reconciliation_candidates(id),
      receipt_transaction_id TEXT NOT NULL REFERENCES transactions(id),
      payment_transaction_id TEXT NOT NULL REFERENCES transactions(id),
      created_at TEXT NOT NULL,
      UNIQUE(receipt_transaction_id, payment_transaction_id)
    )''',
    'CREATE INDEX idx_reconciliation_links_receipt ON reconciliation_links(receipt_transaction_id)',
    'CREATE INDEX idx_reconciliation_links_payment ON reconciliation_links(payment_transaction_id)',
  ];

  static const migration12 = <String>[
    "ALTER TABLE user_preferences ADD COLUMN appearance TEXT NOT NULL DEFAULT 'system'",
    "ALTER TABLE user_preferences ADD COLUMN color_theme TEXT NOT NULL DEFAULT 'butlerRed'",
  ];

  static const migration13 = <String>[
    'ALTER TABLE user_preferences ADD COLUMN formatting_locale TEXT',
    'ALTER TABLE user_preferences ADD COLUMN region_code TEXT',
  ];

  static const migration14 = <String>[
    '''CREATE TABLE category_translations (
      category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
      locale TEXT NOT NULL,
      label TEXT NOT NULL,
      PRIMARY KEY(category_id, locale)
    )''',
    '''CREATE TABLE tag_translations (
      tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
      locale TEXT NOT NULL,
      label TEXT NOT NULL,
      PRIMARY KEY(tag_id, locale)
    )''',
    '''CREATE TABLE reference_data (
      id TEXT PRIMARY KEY NOT NULL,
      code TEXT NOT NULL UNIQUE,
      type TEXT NOT NULL,
      origin TEXT NOT NULL,
      status TEXT NOT NULL
    )''',
    '''CREATE TABLE reference_data_translations (
      reference_data_id TEXT NOT NULL REFERENCES reference_data(id) ON DELETE CASCADE,
      locale TEXT NOT NULL,
      label TEXT NOT NULL,
      PRIMARY KEY(reference_data_id, locale)
    )''',
    'CREATE INDEX idx_reference_data_type ON reference_data(type)',
  ];

  static const migration15 = <String>[
    '''CREATE TABLE normalized_money_v15 (
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      exchange_rate_id TEXT REFERENCES exchange_rates(id),
      amount_coefficient TEXT NOT NULL,
      amount_scale INTEGER NOT NULL CHECK(amount_scale >= 0),
      currency TEXT NOT NULL,
      normalization_source TEXT NOT NULL DEFAULT 'exchangeRate',
      base_currency TEXT NOT NULL,
      effective_date TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY(transaction_id, exchange_rate_id)
    )''',
    '''INSERT INTO normalized_money_v15
      (transaction_id, exchange_rate_id, amount_coefficient, amount_scale,
       currency, base_currency)
      SELECT transaction_id, exchange_rate_id, amount_coefficient, amount_scale,
       currency, currency FROM normalized_money''',
    'DROP TABLE normalized_money',
    'ALTER TABLE normalized_money_v15 RENAME TO normalized_money',
  ];

  static const migration16 = <String>[
    '''CREATE TABLE analysis_rule_definitions (
      rule_id TEXT NOT NULL,
      rule_version TEXT NOT NULL,
      schema_version TEXT NOT NULL,
      source_type TEXT NOT NULL,
      definition TEXT NOT NULL,
      canonical_definition TEXT NOT NULL,
      definition_hash TEXT NOT NULL,
      validation_status TEXT NOT NULL,
      validation_diagnostics TEXT,
      installed_at TEXT NOT NULL,
      retired_at TEXT,
      PRIMARY KEY(rule_id, rule_version)
    )''',
    '''CREATE TABLE analysis_rule_activations (
      rule_id TEXT PRIMARY KEY NOT NULL,
      active_rule_version TEXT NOT NULL,
      enabled INTEGER NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE analysis_rule_configurations (
      rule_id TEXT PRIMARY KEY NOT NULL,
      configuration TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE analysis_findings (
      id TEXT PRIMARY KEY NOT NULL,
      rule_id TEXT NOT NULL,
      rule_version TEXT NOT NULL,
      definition_hash TEXT NOT NULL,
      period_start TEXT NOT NULL,
      period_end TEXT NOT NULL,
      time_zone_id TEXT NOT NULL,
      payload TEXT NOT NULL,
      lifecycle TEXT NOT NULL,
      generated_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    'CREATE INDEX idx_analysis_findings_rule ON analysis_findings(rule_id, rule_version)',
    'CREATE INDEX idx_analysis_findings_lifecycle ON analysis_findings(lifecycle)',
  ];

  static const migration17 = <String>[
    '''CREATE TABLE financial_statements (
      id TEXT PRIMARY KEY NOT NULL,
      evidence_id TEXT NOT NULL UNIQUE REFERENCES evidence_items(id) ON DELETE CASCADE,
      payment_source_id TEXT REFERENCES payment_sources(id),
      status TEXT NOT NULL,
      institution TEXT,
      masked_account_identifier TEXT,
      period_start TEXT,
      period_end TEXT,
      extraction_message TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK ((period_start IS NULL) = (period_end IS NULL))
    )''',
    '''CREATE TABLE statement_rows (
      id TEXT PRIMARY KEY NOT NULL,
      statement_id TEXT NOT NULL REFERENCES financial_statements(id) ON DELETE CASCADE,
      position INTEGER NOT NULL CHECK(position >= 0),
      original_text TEXT NOT NULL,
      transaction_date TEXT,
      posting_date TEXT,
      description TEXT,
      amount TEXT,
      currency TEXT,
      direction TEXT,
      row_kind TEXT NOT NULL,
      confidence REAL CHECK(confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
      source_context TEXT,
      status TEXT NOT NULL,
      transaction_id TEXT REFERENCES transactions(id),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(statement_id, position)
    )''',
    'CREATE INDEX idx_statement_rows_status ON statement_rows(statement_id, status)',
    'CREATE INDEX idx_statements_period ON financial_statements(payment_source_id, period_start, period_end)',
  ];

  static const migration18 = <String>[
    'ALTER TABLE financial_statements ADD COLUMN statement_date TEXT',
    'ALTER TABLE financial_statements ADD COLUMN currency TEXT',
    'ALTER TABLE financial_statements ADD COLUMN opening_balance TEXT',
    'ALTER TABLE financial_statements ADD COLUMN closing_balance TEXT',
    'ALTER TABLE financial_statements ADD COLUMN original_filename TEXT',
    'ALTER TABLE financial_statements ADD COLUMN raw_text_reference TEXT',
  ];

  static const migration19 = <String>[
    'ALTER TABLE statement_rows ADD COLUMN merchant_id TEXT REFERENCES merchants(id)',
    'ALTER TABLE statement_rows ADD COLUMN category_id TEXT REFERENCES categories(id)',
    'ALTER TABLE statement_rows ADD COLUMN tag_ids TEXT',
    'ALTER TABLE statement_rows ADD COLUMN payment_source_id TEXT REFERENCES payment_sources(id)',
    'ALTER TABLE statement_rows ADD COLUMN source_reference_id TEXT',
    'ALTER TABLE statement_rows ADD COLUMN review_reason TEXT',
    'ALTER TABLE statement_rows ADD COLUMN disposition_reason TEXT',
  ];
}
