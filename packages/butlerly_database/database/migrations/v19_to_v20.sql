-- Persist the source of each analysis-rule version independently of the
-- definition row. A missing definition can then be restored only when its
-- original source is known to have been bundled.
CREATE TABLE IF NOT EXISTS analysis_rule_provenance (
      rule_id TEXT NOT NULL,
      rule_version TEXT NOT NULL,
      source_type TEXT NOT NULL,
      definition_hash TEXT NOT NULL,
      recorded_at TEXT NOT NULL,
      PRIMARY KEY(rule_id, rule_version)
    );

INSERT OR IGNORE INTO analysis_rule_provenance (
      rule_id,
      rule_version,
      source_type,
      definition_hash,
      recorded_at
    )
SELECT
      rule_id,
      rule_version,
      source_type,
      definition_hash,
      installed_at
FROM analysis_rule_definitions;
