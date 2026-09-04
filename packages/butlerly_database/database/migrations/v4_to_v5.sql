ALTER TABLE transactions ADD COLUMN subcategory_id TEXT REFERENCES categories(id);
ALTER TABLE transactions ADD COLUMN normalized_description TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_transactions_classification_merchant
  ON transactions(merchant_id, status, category_id, subcategory_id);
CREATE INDEX IF NOT EXISTS idx_transactions_classification_description
  ON transactions(normalized_description, status, category_id, subcategory_id);
