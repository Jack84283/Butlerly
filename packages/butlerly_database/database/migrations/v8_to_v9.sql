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

CREATE TRIGGER payment_settlements_validate_insert
BEFORE INSERT ON payment_settlements
WHEN NOT EXISTS (
  SELECT 1
  FROM transactions t
  WHERE t.id = NEW.settlement_transaction_id
    AND t.direction = 'transfer'
    AND t.status = 'active'
    AND t.payment_source_id = NEW.payment_source_id
    AND t.transaction_date IS NOT NULL
    AND (
      NEW.statement_balance_currency IS NULL
      OR t.currency = NEW.statement_balance_currency
    )
)
BEGIN
  SELECT RAISE(
    ABORT,
    'invalid payment settlement transaction relationship'
  );
END;

CREATE TRIGGER payment_settlements_validate_update
BEFORE UPDATE OF settlement_transaction_id, payment_source_id,
  statement_balance_currency ON payment_settlements
WHEN NOT EXISTS (
  SELECT 1
  FROM transactions t
  WHERE t.id = NEW.settlement_transaction_id
    AND t.direction = 'transfer'
    AND t.status = 'active'
    AND t.payment_source_id = NEW.payment_source_id
    AND t.transaction_date IS NOT NULL
    AND (
      NEW.statement_balance_currency IS NULL
      OR t.currency = NEW.statement_balance_currency
    )
)
BEGIN
  SELECT RAISE(
    ABORT,
    'invalid payment settlement transaction relationship'
  );
END;

CREATE TRIGGER settlement_payment_transaction_validate_update
BEFORE UPDATE OF direction, status, payment_source_id, transaction_date,
  currency ON transactions
WHEN EXISTS (
  SELECT 1
  FROM payment_settlements ps
  WHERE ps.settlement_transaction_id = OLD.id
)
AND (
  NEW.direction != 'transfer'
  OR NEW.status != 'active'
  OR NEW.transaction_date IS NULL
  OR EXISTS (
    SELECT 1
    FROM payment_settlements ps
    WHERE ps.settlement_transaction_id = OLD.id
      AND (
        NEW.payment_source_id IS NULL
        OR NEW.payment_source_id != ps.payment_source_id
        OR (
          ps.statement_balance_currency IS NOT NULL
          AND NEW.currency != ps.statement_balance_currency
        )
      )
  )
)
BEGIN
  SELECT RAISE(
    ABORT,
    'invalid settlement payment transaction update'
  );
END;

CREATE TRIGGER settlement_payment_transaction_review_update
AFTER UPDATE OF amount_coefficient, amount_scale, currency, transaction_date
ON transactions
WHEN (
  OLD.amount_coefficient != NEW.amount_coefficient
  OR OLD.amount_scale != NEW.amount_scale
  OR OLD.currency != NEW.currency
  OR OLD.transaction_date != NEW.transaction_date
)
AND NOT EXISTS (SELECT 1 FROM restore_context WHERE id = 1)
BEGIN
  UPDATE payment_settlements
  SET status = 'needsReview',
      updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE settlement_transaction_id = NEW.id
    AND status != 'needsReview';
END;

