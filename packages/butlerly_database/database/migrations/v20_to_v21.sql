CREATE TABLE IF NOT EXISTS data_integrity_reports (
      id TEXT PRIMARY KEY NOT NULL,
      scanned_at TEXT NOT NULL,
      finding_count INTEGER NOT NULL
    );

CREATE TABLE IF NOT EXISTS data_integrity_findings (
      id TEXT NOT NULL,
      report_id TEXT NOT NULL REFERENCES data_integrity_reports(id) ON DELETE CASCADE,
      code TEXT NOT NULL,
      category TEXT NOT NULL,
      severity TEXT NOT NULL,
      description TEXT NOT NULL,
      affected_records TEXT NOT NULL,
      context TEXT NOT NULL,
      recommended_action TEXT NOT NULL,
      detected_at TEXT NOT NULL,
      PRIMARY KEY(report_id, id)
    );

CREATE INDEX IF NOT EXISTS idx_data_integrity_findings_report
  ON data_integrity_findings(report_id);

CREATE TABLE IF NOT EXISTS operation_diagnostics (
      id TEXT PRIMARY KEY NOT NULL,
      operation TEXT NOT NULL,
      code TEXT NOT NULL,
      category TEXT NOT NULL,
      severity TEXT NOT NULL,
      description TEXT NOT NULL,
      affected_records TEXT NOT NULL,
      context TEXT NOT NULL,
      recommended_action TEXT NOT NULL,
      detected_at TEXT NOT NULL
    );

CREATE INDEX IF NOT EXISTS idx_operation_diagnostics_detected_at
  ON operation_diagnostics(detected_at);
