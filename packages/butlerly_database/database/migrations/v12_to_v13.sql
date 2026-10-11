CREATE TABLE recurring_pattern_decisions (
      id TEXT PRIMARY KEY NOT NULL,
      pattern_key TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL CHECK(status IN ('confirmed', 'rejected', 'corrected')),
      cadence TEXT NOT NULL CHECK(cadence IN ('weekly', 'biweekly', 'monthly', 'quarterly', 'irregular')),
      interval_days INTEGER NOT NULL CHECK(interval_days > 0),
      expected_amount_coefficient TEXT NOT NULL,
      expected_amount_scale INTEGER NOT NULL CHECK(expected_amount_scale >= 0),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

CREATE INDEX idx_recurring_pattern_decisions_key
  ON recurring_pattern_decisions(pattern_key);
