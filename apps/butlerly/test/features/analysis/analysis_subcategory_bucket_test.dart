import 'package:butlerly/features/analysis/presentation/analysis_subcategory_bucket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy leaf category resolves to subcategory for search fallback', () {
    expect(
      analysisSubcategoryBucket(
        categoryId: 'groceries',
        subcategoryId: null,
        parentCategoryId: 'food',
      ),
      'groceries',
    );
  });

  test('modern explicit subcategory is authoritative', () {
    expect(
      analysisSubcategoryBucket(
        categoryId: 'food',
        subcategoryId: 'groceries',
        parentCategoryId: null,
      ),
      'groceries',
    );
  });

  test('category-only and uncategorized transactions remain distinct', () {
    expect(
      analysisSubcategoryBucket(
        categoryId: 'food',
        subcategoryId: null,
        parentCategoryId: null,
      ),
      'no_subcategory',
    );
    expect(
      analysisSubcategoryBucket(
        categoryId: null,
        subcategoryId: null,
        parentCategoryId: null,
      ),
      'uncategorized',
    );
  });
}
