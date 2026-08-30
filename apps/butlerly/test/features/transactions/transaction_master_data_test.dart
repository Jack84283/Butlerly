import 'dart:io';

import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  late ButlerlyDatabase database;
  late SqliteTransactionRepository transactions;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: await File(
        '../../packages/butlerly_database/database/schema/v1.sql',
      ).readAsString(),
    );
    await database.open();
    transactions = SqliteTransactionRepository(database);
  });
  tearDown(() => database.close());

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

  test(
    'persisted master-data keys survive locale switching unchanged',
    () async {
      final now = DateTime.utc(2026, 8, 15);
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
      final categoryRepository = SqliteCategoryRepository(database);
      final tagRepository = SqliteTagRepository(database);
      await categoryRepository.save(parent);
      await categoryRepository.save(category);
      await tagRepository.save(tag);
      final transaction = Transaction(
        id: TransactionId('locale-transaction'),
        timing: KnownTransactionTime(now),
        money: Money(
          amount: DecimalValue.parse('42.19'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.manual,
        categoryId: category.id,
        tagIds: [tag.id],
        provenance: [
          Provenance(
            id: ProvenanceId('locale-provenance'),
            sourceType: ProvenanceSourceType.userEntry,
            capturedAt: now,
            originalRepresentation: 'manual',
          ),
        ],
        createdAt: now,
        updatedAt: now,
        transactionDate: '2026-08-15',
      );
      await transactions.save(transaction);
      final stored = await transactions.findById(transaction.id);
      expect(stored!.categoryId!.value, 'category.food.groceries');
      expect(stored.tagIds.single.value, 'tag.business');

      final english = TransactionMasterData.fromEntities(
        merchants: const [],
        categories: [parent, category],
        tags: [tag],
        categoryLabels: {
          'category.food': 'Food & Dining',
          'category.food.groceries': 'Groceries',
        },
        tagLabels: {'tag.business': 'Business'},
        languageCode: 'en',
      );
      expect(english.categoryName(stored.categoryId!.value), 'Groceries');
      expect(english.tagName(stored.tagIds.single.value), 'Business');

      final chinese = TransactionMasterData.fromEntities(
        merchants: const [],
        categories: [parent, category],
        tags: [tag],
        categoryLabels: {
          'category.food': '餐饮',
          'category.food.groceries': '食品杂货',
        },
        tagLabels: {'tag.business': '商务'},
        languageCode: 'zh-Hans',
      );
      expect(chinese.categoryName(stored.categoryId!.value), '食品杂货');
      expect(chinese.tagName(stored.tagIds.single.value), '商务');

      final reloaded = await transactions.findById(transaction.id);
      expect(reloaded!.categoryId!.value, 'category.food.groceries');
      expect(reloaded.tagIds.single.value, 'tag.business');
      expect(
        await database.connection.query(
          'transactions',
          columns: ['category_id'],
        ),
        hasLength(1),
      );
    },
  );
}
