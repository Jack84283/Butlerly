import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('aliases, patterns, and rules survive database reload', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-match-');
    final databasePath = '${directory.path}/butlerly.db';
    final schema = await File('database/schema/v1.sql').readAsString();
    final now = DateTime.utc(2026, 9, 1, 12);
    final merchant = Merchant(
      id: MerchantId('merchant.costco'),
      name: 'Costco',
      rawName: 'COSTCO #1234',
    );

    Future<ButlerlyDatabase> openDatabase() async {
      final value = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: databasePath,
        schemaSql: schema,
      );
      await value.open();
      return value;
    }

    try {
      var database = await openDatabase();
      await SqliteMerchantRepository(database).save(merchant);
      final aliases = SqliteMerchantAliasRepository(database);
      final patterns = SqliteMerchantNormalizationPatternRepository(database);
      final rules = SqliteTransactionRuleRepository(database);
      final alias = MerchantAlias(
        id: MerchantAliasId('alias.costco'),
        merchantId: merchant.id,
        alias: 'Costco Store 1234',
        createdAt: now,
        updatedAt: now,
      );
      final pattern = MerchantNormalizationPattern(
        id: MerchantNormalizationPatternId('pattern.costco'),
        merchantId: merchant.id,
        pattern: 'COSTCO #1234',
        createdAt: now,
        updatedAt: now,
      );
      final rule = TransactionRule(
        id: TransactionRuleId('rule.costco'),
        name: 'Classify Costco',
        priority: 2,
        descriptionContains: 'fuel',
        assignCategoryId: CategoryId('category.transport'),
        createdAt: now,
        updatedAt: now,
      );
      await aliases.save(alias);
      await patterns.save(pattern);
      await rules.save(rule);
      await database.close();

      database = await openDatabase();
      addTearDown(database.close);
      final loadedMerchant = await SqliteMerchantRepository(
        database,
      ).findById(merchant.id);
      expect(loadedMerchant?.rawName, 'COSTCO #1234');
      expect(loadedMerchant?.aliases.single.alias, alias.alias);
      expect(
        loadedMerchant?.normalizationPatterns.single.pattern,
        pattern.pattern,
      );
      expect(
        (await SqliteMerchantAliasRepository(
          database,
        ).listForMerchant(merchant.id)).single.normalizedAlias,
        'costco',
      );
      expect(
        (await SqliteTransactionRuleRepository(database).listAll()).single,
        isA<TransactionRule>()
            .having((value) => value.name, 'name', rule.name)
            .having((value) => value.priority, 'priority', 2)
            .having(
              (value) => value.assignCategoryId,
              'assignCategoryId',
              CategoryId('category.transport'),
            ),
      );

      await SqliteMerchantAliasRepository(database).remove(alias.id);
      await SqliteMerchantNormalizationPatternRepository(
        database,
      ).remove(pattern.id);
      await SqliteTransactionRuleRepository(database).remove(rule.id);
      expect(
        await SqliteMerchantRepository(database).findById(merchant.id),
        isNotNull,
      );
      expect(
        await SqliteMerchantAliasRepository(
          database,
        ).listForMerchant(merchant.id),
        isEmpty,
      );
    } finally {
      await Directory(directory.path).delete(recursive: true);
    }
  });
}
