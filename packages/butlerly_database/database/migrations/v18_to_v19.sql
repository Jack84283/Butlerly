CREATE TABLE IF NOT EXISTS financial_profiles (
      profile_id TEXT PRIMARY KEY NOT NULL,
      schema_version INTEGER NOT NULL CHECK(schema_version >= 1),
      survey_version TEXT NOT NULL,
      household_size TEXT,
      dependents_count TEXT,
      housing_situation TEXT,
      primary_spending_categories TEXT NOT NULL DEFAULT '[]',
      expense_predictability TEXT,
      categories_to_improve TEXT NOT NULL DEFAULT '[]',
      primary_financial_goal TEXT,
      has_monthly_savings_target INTEGER CHECK(has_monthly_savings_target IN (0, 1)),
      monthly_savings_target TEXT,
      monthly_savings_target_currency TEXT,
      goal_timeframe TEXT,
      budgeting_preference TEXT,
      preferred_insight_types TEXT NOT NULL DEFAULT '[]',
      survey_status TEXT NOT NULL CHECK(survey_status IN ('notStarted', 'inProgress', 'completed')),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      completed_at TEXT,
      CHECK (
        (monthly_savings_target IS NULL AND monthly_savings_target_currency IS NULL)
        OR (monthly_savings_target IS NOT NULL AND monthly_savings_target_currency IS NOT NULL)
      )
    );
