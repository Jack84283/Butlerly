ALTER TABLE statement_rows ADD COLUMN subcategory_id TEXT REFERENCES categories(id);
