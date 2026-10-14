-- Normalize persisted transaction instants. Prefer a valid occurred_at_utc
-- value, then a valid occurred_at value. If neither can be recovered, retain
-- the transaction with the existing unknown-time representation instead of
-- leaving a value that DateTime.parse() cannot hydrate.
UPDATE transactions
SET occurred_at = CASE
      WHEN julianday(occurred_at_utc) IS NOT NULL
        THEN strftime('%Y-%m-%dT%H:%M:%fZ', occurred_at_utc)
      WHEN julianday(occurred_at) IS NOT NULL
        THEN strftime('%Y-%m-%dT%H:%M:%fZ', occurred_at)
      ELSE NULL
    END,
    occurred_at_utc = CASE
      WHEN julianday(occurred_at_utc) IS NOT NULL
        THEN strftime('%Y-%m-%dT%H:%M:%fZ', occurred_at_utc)
      WHEN julianday(occurred_at) IS NOT NULL
        THEN strftime('%Y-%m-%dT%H:%M:%fZ', occurred_at)
      ELSE NULL
    END,
    unknown_time_reason = CASE
      WHEN julianday(occurred_at_utc) IS NOT NULL
        OR julianday(occurred_at) IS NOT NULL
        THEN NULL
      ELSE COALESCE(NULLIF(unknown_time_reason, ''), 'unknown')
    END
WHERE occurred_at IS NOT NULL OR occurred_at_utc IS NOT NULL;
