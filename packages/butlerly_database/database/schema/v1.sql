PRAGMA foreign_keys = ON;

CREATE TABLE analysis_findings (
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
    );

CREATE TABLE analysis_rule_activations (
      rule_id TEXT PRIMARY KEY NOT NULL,
      active_rule_version TEXT NOT NULL,
      enabled INTEGER NOT NULL,
      updated_at TEXT NOT NULL
    );

CREATE TABLE analysis_rule_configurations (
      rule_id TEXT PRIMARY KEY NOT NULL,
      configuration TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

CREATE TABLE analysis_rule_definitions (
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
    );

CREATE TABLE attachment_links (
      id TEXT PRIMARY KEY NOT NULL,
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      evidence_id TEXT NOT NULL REFERENCES evidence_items(id),
      created_at TEXT NOT NULL,
      UNIQUE(transaction_id, evidence_id)
    );

CREATE TABLE categories (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      origin TEXT NOT NULL
    , parent_id TEXT REFERENCES categories(id), status TEXT NOT NULL DEFAULT 'active');

CREATE TABLE category_translations (
      category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
      locale TEXT NOT NULL,
      label TEXT NOT NULL,
      PRIMARY KEY(category_id, locale)
    );

CREATE TABLE duplicate_candidate_group_transactions (
      group_id TEXT NOT NULL REFERENCES duplicate_candidate_groups(id) ON DELETE CASCADE,
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      PRIMARY KEY(group_id, transaction_id)
    );

CREATE TABLE duplicate_candidate_groups (
      id TEXT PRIMARY KEY NOT NULL,
      transaction_date TEXT NOT NULL,
      amount_coefficient TEXT NOT NULL,
      amount_scale INTEGER NOT NULL CHECK(amount_scale >= 0),
      currency TEXT NOT NULL,
      direction TEXT NOT NULL,
      status TEXT NOT NULL,
      selected_transaction_id TEXT REFERENCES transactions(id),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

CREATE TABLE evidence_items (
      id TEXT PRIMARY KEY NOT NULL,
      type TEXT NOT NULL,
      original_name TEXT NOT NULL,
      media_type TEXT NOT NULL,
      provenance_id TEXT NOT NULL REFERENCES provenances(id),
      created_at TEXT NOT NULL,
      source_language TEXT
    , local_file_name TEXT);

CREATE TABLE exchange_rates (
      id TEXT PRIMARY KEY NOT NULL,
      from_currency TEXT NOT NULL,
      to_currency TEXT NOT NULL,
      rate_coefficient TEXT NOT NULL,
      rate_scale INTEGER NOT NULL CHECK(rate_scale >= 0),
      effective_at TEXT NOT NULL,
      source TEXT NOT NULL
    );

CREATE TABLE extractions (
      id TEXT PRIMARY KEY NOT NULL,
      evidence_id TEXT NOT NULL REFERENCES evidence_items(id) ON DELETE CASCADE,
      values_json TEXT NOT NULL,
      provenance_id TEXT NOT NULL REFERENCES provenances(id),
      created_at TEXT NOT NULL
    );

CREATE TABLE financial_statements (
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
      updated_at TEXT NOT NULL, statement_date TEXT, currency TEXT, opening_balance TEXT, closing_balance TEXT, original_filename TEXT, raw_text_reference TEXT,
      CHECK ((period_start IS NULL) = (period_end IS NULL))
    );

CREATE TABLE merchants (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL
    , status TEXT NOT NULL DEFAULT 'active', raw_name TEXT);

CREATE TABLE normalized_money (transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE, exchange_rate_id TEXT REFERENCES exchange_rates(id), amount_coefficient TEXT NOT NULL, amount_scale INTEGER NOT NULL CHECK(amount_scale >= 0), currency TEXT NOT NULL, normalization_source TEXT NOT NULL DEFAULT 'exchangeRate', base_currency TEXT NOT NULL, effective_date TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(transaction_id, exchange_rate_id));

CREATE TABLE payment_sources (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      status TEXT NOT NULL
    , display_identity TEXT, last_four TEXT, issuer TEXT, currency TEXT, note TEXT);

CREATE TABLE provenances (
      id TEXT PRIMARY KEY NOT NULL,
      source_type TEXT NOT NULL,
      captured_at TEXT NOT NULL,
      source_id TEXT,
      original_representation TEXT,
      source_language TEXT
    );

CREATE TABLE reconciliation_candidates (
      id TEXT PRIMARY KEY NOT NULL,
      receipt_transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      payment_transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      score REAL NOT NULL CHECK(score >= 0 AND score <= 1),
      reasons_json TEXT NOT NULL,
      status TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(receipt_transaction_id, payment_transaction_id)
    );

CREATE TABLE reconciliation_links (
      id TEXT PRIMARY KEY NOT NULL,
      candidate_id TEXT NOT NULL UNIQUE REFERENCES reconciliation_candidates(id),
      receipt_transaction_id TEXT NOT NULL REFERENCES transactions(id),
      payment_transaction_id TEXT NOT NULL REFERENCES transactions(id),
      created_at TEXT NOT NULL,
      UNIQUE(receipt_transaction_id, payment_transaction_id)
    );

CREATE TABLE reference_data (
      id TEXT PRIMARY KEY NOT NULL,
      code TEXT NOT NULL,
      type TEXT NOT NULL,
      origin TEXT NOT NULL,
      status TEXT NOT NULL
    );

CREATE TABLE reference_data_translations (
      reference_data_id TEXT NOT NULL REFERENCES reference_data(id) ON DELETE CASCADE,
      locale TEXT NOT NULL,
      label TEXT NOT NULL,
      PRIMARY KEY(reference_data_id, locale)
    );

CREATE TABLE review_issues (
      id TEXT PRIMARY KEY NOT NULL,
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      reason TEXT NOT NULL,
      status TEXT NOT NULL,
      detail TEXT,
      created_at TEXT NOT NULL,
      closed_at TEXT
    );

CREATE TABLE statement_rows (
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
      updated_at TEXT NOT NULL, merchant_id TEXT REFERENCES merchants(id), category_id TEXT REFERENCES categories(id), tag_ids TEXT, payment_source_id TEXT REFERENCES payment_sources(id), source_reference_id TEXT, review_reason TEXT, disposition_reason TEXT, status_before_skip TEXT,
      UNIQUE(statement_id, position)
    );

CREATE TABLE suggestions (
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
    );

CREATE TABLE tag_translations (
      tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
      locale TEXT NOT NULL,
      label TEXT NOT NULL,
      PRIMARY KEY(tag_id, locale)
    );

CREATE TABLE tags (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL
    , status TEXT NOT NULL DEFAULT 'active');

CREATE TABLE transaction_provenances (
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      provenance_id TEXT NOT NULL REFERENCES provenances(id),
      PRIMARY KEY(transaction_id, provenance_id)
    );

CREATE TABLE transaction_tags (
      transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
      tag_id TEXT NOT NULL REFERENCES tags(id),
      PRIMARY KEY(transaction_id, tag_id)
    );

CREATE TABLE transactions (
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
      updated_at TEXT NOT NULL, transaction_date TEXT, occurred_at_utc TEXT, time_zone_id TEXT, external_reference TEXT,
      CHECK ((occurred_at IS NOT NULL) != (unknown_time_reason IS NOT NULL))
    );

CREATE TABLE user_preferences (
      id INTEGER PRIMARY KEY NOT NULL CHECK(id = 1),
      locale TEXT NOT NULL,
      base_currency TEXT NOT NULL,
      time_zone_id TEXT NOT NULL,
      external_ai_enabled INTEGER NOT NULL CHECK(external_ai_enabled IN (0, 1))
    , first_use_completed INTEGER NOT NULL DEFAULT 0 CHECK(first_use_completed IN (0, 1)), formatting_locale TEXT, region_code TEXT, appearance TEXT NOT NULL DEFAULT 'system', color_theme TEXT NOT NULL DEFAULT 'butlerRed');

CREATE INDEX idx_analysis_findings_lifecycle ON analysis_findings(lifecycle);

CREATE INDEX idx_analysis_findings_rule ON analysis_findings(rule_id, rule_version);

CREATE INDEX idx_attachment_links_transaction ON attachment_links(transaction_id);

CREATE INDEX idx_categories_parent ON categories(parent_id);

CREATE INDEX idx_duplicate_group_transactions_transaction ON duplicate_candidate_group_transactions(transaction_id);

CREATE INDEX idx_duplicate_groups_status ON duplicate_candidate_groups(status);

CREATE INDEX idx_reconciliation_candidates_status ON reconciliation_candidates(status);

CREATE INDEX idx_reconciliation_links_payment ON reconciliation_links(payment_transaction_id);

CREATE INDEX idx_reconciliation_links_receipt ON reconciliation_links(receipt_transaction_id);

CREATE INDEX idx_reference_data_type ON reference_data(type);

CREATE INDEX idx_review_issues_active ON review_issues(transaction_id, status);

CREATE INDEX idx_statement_rows_status ON statement_rows(statement_id, status);

CREATE INDEX idx_statements_period ON financial_statements(payment_source_id, period_start, period_end);

CREATE INDEX idx_transactions_category ON transactions(category_id);

CREATE INDEX idx_transactions_duplicate_group_lookup ON transactions(transaction_date, amount_coefficient, amount_scale, currency, direction, status);

CREATE INDEX idx_transactions_external_reference ON transactions(external_reference);

CREATE INDEX idx_transactions_merchant ON transactions(merchant_id);

CREATE INDEX idx_transactions_occurred_at ON transactions(occurred_at);

CREATE INDEX idx_transactions_transaction_date ON transactions(transaction_date);
