import 'package:butlerly/features/foundation/presentation/master_data_labels.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('system labels switch language without changing stable IDs', () {
    final category = Category(
      id: CategoryId('category.food'),
      name: 'Food & Dining',
      origin: CategoryOrigin.system,
    );

    expect(categoryDisplayLabel(category, 'en'), 'Food & Dining');
    expect(categoryDisplayLabel(category, 'zh'), '餐饮');
    expect(category.id.value, 'category.food');
  });

  test('user-created labels are never translated by the system catalog', () {
    final category = Category(
      id: CategoryId('custom-food'),
      name: '我的餐馆',
      origin: CategoryOrigin.user,
    );
    final tag = Tag(id: TagId('custom-tag'), name: '出差');

    expect(categoryDisplayLabel(category, 'en'), '我的餐馆');
    expect(tagDisplayLabel(tag, 'zh'), '出差');
  });

  test(
    'legacy system category names still resolve to MD-0001 translations',
    () {
      final legacy = Category(
        id: CategoryId('system-category-food-dining'),
        name: 'Food & dining',
        origin: CategoryOrigin.system,
      );

      expect(categoryDisplayLabel(legacy, 'zh'), '餐饮');
    },
  );
}
