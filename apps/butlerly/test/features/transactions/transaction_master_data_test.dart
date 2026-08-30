import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stable category and tag keys resolve to locale labels without rewriting',
    () {
      final category = Category(
        id: CategoryId('category.food.groceries'),
        name: 'Groceries',
        origin: CategoryOrigin.system,
        parentId: CategoryId('category.food'),
      );
      final parent = Category(
        id: CategoryId('category.food'),
        name: 'Food & Dining',
        origin: CategoryOrigin.system,
      );
      final tag = Tag(id: TagId('tag.business'), name: 'Business');
      final data = TransactionMasterData.fromEntities(
        merchants: const [],
        categories: [parent, category],
        tags: [tag],
        categoryLabels: {
          'category.food': '餐饮',
          'category.food.groceries': '食品杂货',
        },
        tagLabels: {'tag.business': '商务'},
        englishCategoryLabels: {
          'category.food': 'Food & Dining',
          'category.food.groceries': 'Groceries',
        },
        englishTagLabels: {'tag.business': 'Business'},
        languageCode: 'zh-Hans',
      );

      expect(data.categoryName('category.food.groceries'), '食品杂货');
      expect(data.categoryNameForParent('category.food.groceries'), '餐饮');
      expect(data.tagName('tag.business'), '商务');
      expect(category.id.value, 'category.food.groceries');
      expect(tag.id.value, 'tag.business');
    },
  );

  test('user-created names remain original when locale changes', () {
    final data = TransactionMasterData.fromEntities(
      merchants: const [],
      categories: [
        Category(
          id: CategoryId('custom-food'),
          name: '我的餐馆',
          origin: CategoryOrigin.user,
        ),
      ],
      tags: [Tag(id: TagId('custom-tag'), name: '出差')],
      categoryLabels: const {},
      tagLabels: const {},
      languageCode: 'en',
    );
    expect(data.categoryName('custom-food'), '我的餐馆');
    expect(data.tagName('custom-tag'), '出差');
  });
}
