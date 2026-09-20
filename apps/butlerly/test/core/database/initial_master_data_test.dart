import 'dart:io';

import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test(
    'database-owned catalog provides MD-0001 master and reference data',
    () async {
      final root = await Directory.systemTemp.createTemp('butlerly-catalog-');
      addTearDown(() => root.delete(recursive: true));
      final database = LocalDatabase(
        logger: AppLogger(),
        factory: databaseFactoryFfi,
        databaseDirectory: root.path,
      );
      await database.initialize();
      addTearDown(database.close);

      final categories = await database.database.query('categories');
      final tags = await database.database.query('tags');
      final merchants = await database.database.query('merchants');
      final referenceData = await database.database.query('reference_data');
      final categoryTranslations = await database.database.query(
        'category_translations',
      );
      final tagTranslations = await database.database.query('tag_translations');
      final referenceTranslations = await database.database.query(
        'reference_data_translations',
      );

      expect(
        categories.map((row) => row['id']),
        containsAll([
          'category.food',
          'category.food.coffee',
          'category.shopping.general',
          'category.household',
          'category.household.cleaning',
          'category.travel.car_rental',
          'category.education.tuition_fees',
          'category.education.books_supplies',
          'category.education.training_courses',
          'category.personal.oral',
          'category.personal.hair',
          'category.personal.bath_body',
          'category.insurance.auto',
          'category.insurance.homeowners',
          'category.insurance.health',
          'category.insurance.life',
          'category.insurance.other',
          'category.income.tax_refund',
          'category.income.interest',
          'category.income.dividends',
          'category.income.rental',
          'category.income.reimbursement',
          'category.professional_services',
          'category.professional_services.tax_preparation',
          'category.taxes.income',
          'category.taxes.property',
          'category.taxes.sales_use',
          'category.taxes.other',
        ]),
      );
      expect(tags.map((row) => row['id']), contains('tag.tax_related'));
      expect(
        merchants.map((row) => row['name']),
        containsAll([
          'Safeway',
          'Kroger',
          'H-E-B',
          'ALDI',
          "Andronico's Community Markets",
          'Albertsons',
          'Costco',
          'Starbucks',
          'Uber',
        ]),
      );
      expect(
        referenceData.map((row) => row['id']),
        containsAll([
          'transaction.direction.expense',
          'payment_source.type.credit_card',
          'card_network.visa',
          'evidence.type.receipt',
          'review.status.needs_review',
          'reconciliation.status.candidate',
          'analysis.finding.data_quality',
        ]),
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.food' &&
                  row['locale'] == 'zh-Hans',
            )
            .single['label'],
        '餐饮',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.food' &&
                  row['locale'] == 'es',
            )
            .single['label'],
        'Comida y restaurantes',
      );
      expect(
        tagTranslations
            .where(
              (row) => row['tag_id'] == 'tag.business' && row['locale'] == 'es',
            )
            .single['label'],
        'Negocios',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.shopping.general' &&
                  row['locale'] == 'es',
            )
            .single['label'],
        'Mercancía general',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.travel.car_rental' &&
                  row['locale'] == 'zh-Hans',
            )
            .single['label'],
        '租车',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.income.tax_refund' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Tax Refund',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.income.refund' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Merchant Refund',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] ==
                      'category.professional_services.tax_preparation' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Tax Preparation',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.taxes.income' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Income Tax',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.taxes.property' &&
                  row['locale'] == 'zh-Hans',
            )
            .single['label'],
        '房产税',
      );
      expect(
        referenceTranslations
            .where(
              (row) =>
                  row['reference_data_id'] ==
                      'payment_source.type.credit_card' &&
                  row['locale'] == 'zh-Hans',
            )
            .single['label'],
        '信用卡',
      );
    },
  );

  test(
    'database-owned catalog reseeds idempotently after system rows are removed',
    () async {
      final root = await Directory.systemTemp.createTemp('butlerly-reseed-');
      addTearDown(() => root.delete(recursive: true));
      final database = LocalDatabase(
        logger: AppLogger(),
        factory: databaseFactoryFfi,
        databaseDirectory: root.path,
      );
      await database.initialize();
      addTearDown(database.close);

      await database.database.delete('reference_data_translations');
      await database.database.delete('reference_data');
      await database.database.delete('tag_translations');
      await database.database.delete('tags');
      await database.database.delete('category_translations');
      await database.database.delete('merchants');
      await database.database.delete('categories');
      expect(await database.database.query('categories'), isEmpty);
      expect(await database.database.query('reference_data'), isEmpty);

      await database.reseedSystemData();
      final first = await database.database.query('categories');
      await database.reseedSystemData();
      final second = await database.database.query('categories');

      expect(first, isNotEmpty);
      expect(second.length, first.length);
    },
  );
}
