ALTER TABLE analysis_rule_results
  ADD COLUMN period_type TEXT NOT NULL DEFAULT 'selected_period';
