import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repository-provided labels localize system IDs without changing them', () {
    final category = Category(
      id: CategoryId('category.food'),
      name: 'Food & Dining',
      origin: CategoryOrigin.system,
    );
    final tag = Tag(id: TagId('tag.business'), name: 'Business');

    final data = TransactionMasterData.fromEntities(
      merchants: const [],
      categories: [category],
      tags: [tag],
      categoryLabels: const {'category.food': '餐饮'},
      tagLabels: const {'tag.business': '商务'},
      languageCode: 'zh',
    );

    expect(data.categoryName(category.id.value), '餐饮');
    expect(data.tagName(tag.id.value), '商务');
    expect(category.id.value, 'category.food');
  });

  test('user-created values remain unchanged when no system translation exists', () {
    final category = Category(
      id: CategoryId('custom-food'),
      name: '我的餐馆',
      origin: CategoryOrigin.user,
    );
    final tag = Tag(id: TagId('custom-tag'), name: '出差');

    final data = TransactionMasterData.fromEntities(
      merchants: const [],
      categories: [category],
      tags: [tag],
      categoryLabels: const {},
      tagLabels: const {},
      languageCode: 'en',
    );

    expect(data.categoryName(category.id.value), '我的餐馆');
    expect(data.tagName(tag.id.value), '出差');
  });
}
