CREATE TABLE budgets (
      id TEXT PRIMARY KEY NOT NULL,
      scope TEXT NOT NULL CHECK(scope IN ('overall', 'category', 'subcategory', 'merchant')),
      scope_id TEXT,
      currency TEXT NOT NULL,
      amount TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      CHECK ((scope = 'overall' AND scope_id IS NULL)
          OR (scope != 'overall' AND scope_id IS NOT NULL)),
      UNIQUE (scope, scope_id, currency)
    );
