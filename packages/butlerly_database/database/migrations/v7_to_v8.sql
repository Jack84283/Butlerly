-- Insight dismissal was removed from the V1 UI. Analysis findings/results are
-- derived and rebuildable, so clear only the Insights surface cache/state once
-- during upgrade. Canonical financial records are intentionally untouched.
DELETE FROM analysis_findings
WHERE rule_id IN (
  'ANL-R014',
  'ANL-R020',
  'ANL-R021',
  'ANL-R022',
  'ANL-R023',
  'ANL-R024',
  'ANL-R025',
  'ANL-R026'
);

DELETE FROM analysis_rule_results
WHERE surface = 'insights';
