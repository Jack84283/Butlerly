CREATE TABLE payment_settlements (
  id TEXT PRIMARY KEY NOT NULL,
  payment_source_id TEXT NOT NULL REFERENCES payment_sources(id),
  funding_payment_source_id TEXT REFERENCES payment_sources(id),
  payment_amount_coefficient TEXT NOT NULL,
  payment_amount_scale INTEGER NOT NULL CHECK(payment_amount_scale >= 0),
  currency TEXT NOT NULL,
  payment_date TEXT NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  statement_balance_coefficient TEXT,
  statement_balance_scale INTEGER CHECK(statement_balance_scale IS NULL OR statement_balance_scale >= 0),
  status TEXT NOT NULL,
  description TEXT,
  external_reference TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK(period_end >= period_start),
  CHECK(
    (statement_balance_coefficient IS NULL) =
    (statement_balance_scale IS NULL)
  )
);

CREATE INDEX payment_settlements_payment_source_date_idx
  ON payment_settlements(payment_source_id, payment_date DESC);

CREATE INDEX payment_settlements_period_idx
  ON payment_settlements(payment_source_id, period_start, period_end);

CREATE INDEX transactions_payment_source_date_idx
  ON transactions(payment_source_id, transaction_date);
