/// Resolves the subcategory grouping key for transaction drill-through.
///
/// The Analysis dataset normalizes legacy rows that keep a leaf ID in the
/// category field. The fallback transaction query must use identical grouping
/// semantics; otherwise a metric with no embedded evidence returns the wrong
/// rows (or none at all).
String analysisSubcategoryBucket({
  required String? categoryId,
  required String? subcategoryId,
  required String? parentCategoryId,
}) =>
    subcategoryId ??
    (parentCategoryId == null ? null : categoryId) ??
    (categoryId == null ? 'uncategorized' : 'no_subcategory');
