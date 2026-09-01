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
