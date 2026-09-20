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
          'category.health.hospital',
          'category.health.dental',
          'category.health.vision',
          'category.health.mental',
          'category.housing.landscaping',
          'category.utilities',
          'category.utilities.electricity',
          'category.utilities.gas',
          'category.utilities.water_sewer',
          'category.utilities.trash_recycling',
          'category.utilities.internet',
          'category.utilities.mobile_phone',
          'category.utilities.cable_tv',
          'category.utilities.other',
          'category.digital_services',
          'category.digital_services.cloud_storage',
          'category.digital_services.software_subscription',
          'category.digital_services.productivity',
          'category.digital_services.online_services',
          'category.digital_services.other',
          'category.gifts.personal',
          'category.gifts.family_support',
          'category.gifts.charity',
          'category.gifts.religious',
          'category.gifts.crowdfunding',
          'category.gifts.other',
          'category.fees.bank',
          'category.fees.credit_card',
          'category.fees.atm',
          'category.fees.late_penalty',
          'category.fees.foreign_transaction',
          'category.fees.transfer_wire',
          'category.fees.account_service',
          'category.fees.other',
          'category.transfer.own_accounts',
          'category.transfer.credit_card_payment',
          'category.transfer.brokerage',
          'category.transfer.savings',
          'category.transfer.cash',
          'category.transfer.other',
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
          'Netflix',
          'Apple iCloud',
          'Shopify',
          'Sprouts',
          '99 Ranch Market',
          'H Mart',
          'McDonald\'s',
          'Best Buy',
          'Kaiser Permanente',
          'Caltrain',
          'United Airlines',
          'Marriott',
          'AT&T',
          'PG&E',
          'Dropbox',
          'Microsoft 365',
          'Adobe',
          'OpenAI / ChatGPT',
          'Disney+',
          'Spotify',
          'Venmo',
          'PayPal',
          'Holiday Inn',
          'Comfort Inn',
          'Motel 6',
          'Super 8',
          'Hampton Inn',
          'Best Western',
          'Days Inn',
          'La Quinta',
          'Courtyard by Marriott',
          'Residence Inn',
          'DoubleTree',
          'Embassy Suites',
          'Sheraton',
          'Westin',
          'Texaco',
          'BP',
          'Speedway',
          'Marathon',
          'Sunoco',
          'Sinclair',
          'Phillips 66',
          'Circle K',
          'QuikTrip',
          'Wawa',
          'Sheetz',
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
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.health.medical' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Medical Care',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.health.pharmacy' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Pharmacy & Prescriptions',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.health.dental' &&
                  row['locale'] == 'zh-Hans',
            )
            .single['label'],
        '牙科',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.utilities.internet' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Internet',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.housing.landscaping' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Yard & Landscaping',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.digital_services.cloud_storage' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Cloud Storage',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.gifts.charity' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Charitable Donations',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.fees.foreign_transaction' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Foreign Transaction Fees',
      );
      expect(
        categoryTranslations
            .where(
              (row) =>
                  row['category_id'] == 'category.transfer.credit_card_payment' &&
                  row['locale'] == 'en',
            )
            .single['label'],
        'Credit Card Payment',
      );
      final netflix = merchants.singleWhere(
        (row) => row['id'] == 'merchant.netflix',
      );
      expect(netflix['default_category_id'], 'category.entertainment');
      expect(
        netflix['default_subcategory_id'],
        'category.entertainment.streaming',
      );
      final iCloud = merchants.singleWhere(
        (row) => row['id'] == 'merchant.apple_icloud',
      );
      expect(iCloud['default_category_id'], 'category.digital_services');
      expect(
        iCloud['default_subcategory_id'],
        'category.digital_services.cloud_storage',
      );
      final shopify = merchants.singleWhere(
        (row) => row['id'] == 'merchant.shopify',
      );
      expect(shopify['default_category_id'], 'category.digital_services');
      expect(
        shopify['default_subcategory_id'],
        'category.digital_services.online_services',
      );
      for (final merchantId in [
        'merchant.walmart',
        'merchant.amazon',
        'merchant.target',
      ]) {
        final merchant = merchants.singleWhere(
          (row) => row['id'] == merchantId,
        );
        expect(merchant['default_category_id'], 'category.shopping');
        expect(
          merchant['default_subcategory_id'],
          'category.shopping.general',
        );
      }
      final caltrain = merchants.singleWhere(
        (row) => row['id'] == 'merchant.caltrain',
      );
      expect(caltrain['default_category_id'], 'category.transportation');
      expect(
        caltrain['default_subcategory_id'],
        'category.transportation.public',
      );
      final att = merchants.singleWhere(
        (row) => row['id'] == 'merchant.att',
      );
      expect(att['default_category_id'], 'category.utilities');
      expect(att['default_subcategory_id'], isNull);
      final pge = merchants.singleWhere(
        (row) => row['id'] == 'merchant.pge',
      );
      expect(pge['default_category_id'], 'category.utilities');
      expect(pge['default_subcategory_id'], isNull);
      final paypal = merchants.singleWhere(
        (row) => row['id'] == 'merchant.paypal',
      );
      expect(paypal['default_category_id'], isNull);
      expect(paypal['default_subcategory_id'], isNull);
      final venmo = merchants.singleWhere(
        (row) => row['id'] == 'merchant.venmo',
      );
      expect(venmo['default_category_id'], isNull);
      expect(venmo['default_subcategory_id'], isNull);
      for (final merchantId in [
        'merchant.holiday_inn',
        'merchant.comfort_inn',
        'merchant.motel_6',
        'merchant.super_8',
        'merchant.hampton_inn',
        'merchant.best_western',
        'merchant.days_inn',
        'merchant.la_quinta',
      ]) {
        final merchant = merchants.singleWhere(
          (row) => row['id'] == merchantId,
        );
        expect(merchant['default_category_id'], 'category.travel');
        expect(merchant['default_subcategory_id'], 'category.travel.hotel');
      }
      for (final merchantId in [
        'merchant.texaco',
        'merchant.bp',
        'merchant.speedway',
        'merchant.marathon',
        'merchant.sunoco',
        'merchant.sinclair',
        'merchant.phillips_66',
        'merchant.circle_k',
        'merchant.quiktrip',
        'merchant.wawa',
        'merchant.sheetz',
      ]) {
        final merchant = merchants.singleWhere(
          (row) => row['id'] == merchantId,
        );
        expect(merchant['default_category_id'], 'category.transportation');
        expect(
          merchant['default_subcategory_id'],
          'category.transportation.fuel',
        );
      }
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
