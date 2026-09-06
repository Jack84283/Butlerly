ALTER TABLE statement_rows ADD COLUMN subcategory_id TEXT REFERENCES categories(id);

UPDATE statement_rows
SET
  subcategory_id = category_id,
  category_id = (
    SELECT parent_id
    FROM categories
    WHERE categories.id = statement_rows.category_id
  )
WHERE subcategory_id IS NULL
  AND category_id IN (
    SELECT id
    FROM categories
    WHERE parent_id IS NOT NULL
  );
