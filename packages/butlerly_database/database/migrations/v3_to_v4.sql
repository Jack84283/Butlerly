ALTER TABLE merchants ADD COLUMN normalized_name TEXT NOT NULL DEFAULT '';
ALTER TABLE merchants ADD COLUMN default_category_id TEXT REFERENCES categories(id);
ALTER TABLE merchants ADD COLUMN default_subcategory_id TEXT REFERENCES categories(id);
ALTER TABLE merchants ADD COLUMN is_built_in INTEGER NOT NULL DEFAULT 0;

UPDATE merchants
SET normalized_name = lower(trim(name))
WHERE normalized_name = '';
