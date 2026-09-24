CREATE TABLE payment_settlements (
  id TEXT PRIMARY KEY NOT NULL,
  settlement_transaction_id TEXT NOT NULL UNIQUE REFERENCES transactions(id) ON DELETE CASCADE,
  payment_source_id TEXT NOT NULL REFERENCES payment_sources(id),
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  statement_balance_coefficient TEXT,
  statement_balance_scale INTEGER CHECK(statement_balance_scale IS NULL OR statement_balance_scale >= 0),
  statement_balance_currency TEXT,
  status TEXT NOT NULL,
  description TEXT,
  external_reference TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK(period_end >= period_start),
  CHECK(
    (statement_balance_coefficient IS NULL) =
    (statement_balance_scale IS NULL)
    AND
    (statement_balance_scale IS NULL) =
    (statement_balance_currency IS NULL)
  )
);

CREATE INDEX payment_settlements_payment_source_period_idx
  ON payment_settlements(payment_source_id, period_start, period_end);

CREATE INDEX transactions_payment_source_date_idx
  ON transactions(payment_source_id, transaction_date);

CREATE TRIGGER payment_settlements_tombstone AFTER DELETE ON payment_settlements
BEGIN
  INSERT INTO entity_tombstones(entity_type, entity_id, deleted_at)
  VALUES('payment_settlements', OLD.id, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
  ON CONFLICT(entity_type, entity_id)
  DO UPDATE SET deleted_at = excluded.deleted_at;
END;

CREATE TRIGGER payment_settlements_tombstone_clear AFTER INSERT ON payment_settlements
BEGIN
  DELETE FROM entity_tombstones
  WHERE entity_type = 'payment_settlements' AND entity_id = NEW.id;
END;
