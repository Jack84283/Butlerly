CREATE TEMP TABLE settlement_payment_transaction_ids AS
SELECT settlement_transaction_id AS id
FROM payment_settlements;

DROP TRIGGER IF EXISTS payment_settlements_validate_insert;
DROP TRIGGER IF EXISTS payment_settlements_validate_update;
DROP TRIGGER IF EXISTS settlement_payment_transaction_validate_update;
DROP TRIGGER IF EXISTS settlement_payment_transaction_review_update;
DROP TRIGGER IF EXISTS payment_settlements_tombstone;
DROP TRIGGER IF EXISTS payment_settlements_tombstone_clear;

ALTER TABLE payment_settlements RENAME TO payment_settlements_v9;

CREATE TABLE payment_settlements (
  id TEXT PRIMARY KEY NOT NULL,
  payment_source_id TEXT NOT NULL REFERENCES payment_sources(id),
  payment_amount_coefficient TEXT NOT NULL,
  payment_amount_scale INTEGER NOT NULL CHECK(payment_amount_scale >= 0),
  payment_currency TEXT NOT NULL,
  payment_date TEXT NOT NULL,
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
  ),
  CHECK(
    statement_balance_currency IS NULL
    OR statement_balance_currency = payment_currency
  )
);

INSERT INTO payment_settlements (
  id,
  payment_source_id,
  payment_amount_coefficient,
  payment_amount_scale,
  payment_currency,
  payment_date,
  period_start,
  period_end,
  statement_balance_coefficient,
  statement_balance_scale,
  statement_balance_currency,
  status,
  description,
  external_reference,
  created_at,
  updated_at
)
SELECT
  ps.id,
  ps.payment_source_id,
  t.amount_coefficient,
  t.amount_scale,
  t.currency,
  t.transaction_date,
  ps.period_start,
  ps.period_end,
  ps.statement_balance_coefficient,
  ps.statement_balance_scale,
  ps.statement_balance_currency,
  ps.status,
  ps.description,
  ps.external_reference,
  ps.created_at,
  ps.updated_at
FROM payment_settlements_v9 ps
JOIN transactions t ON t.id = ps.settlement_transaction_id;

DROP TABLE payment_settlements_v9;

DELETE FROM transactions
WHERE id IN (SELECT id FROM settlement_payment_transaction_ids);

DROP TABLE settlement_payment_transaction_ids;

CREATE INDEX payment_settlements_payment_source_period_idx
  ON payment_settlements(payment_source_id, period_start, period_end);

CREATE INDEX payment_settlements_payment_date_idx
  ON payment_settlements(payment_date);

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
