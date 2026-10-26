import 'dart:io';

import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late LocalDatabase database;
  late FinanceServices finance;

  setUp(() async {
    await services.reset();
    directory = await Directory.systemTemp.createTemp(
      'butlerly-budget-actual-',
    );
    database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: directory.path,
    );
    await database.initialize();
    configureDependencies(
      configuration: const AppConfiguration(),
      database: database,
      logger: AppLogger(),
    );
    finance = services<FinanceServices>();
  });

  tearDown(() async {
    await services.reset();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'newly saved merchant budget returns zero without analysis rules',
    () async {
      await SqliteUserPreferenceRepository(database.persistenceDatabase).save(
        UserPreference(
          locale: 'en',
          baseCurrency: CurrencyCode('USD'),
          timeZoneId: 'America/Los_Angeles',
        ),
      );
      const budget = Budget(
        id: 'merchant-budget-new',
        scope: 'merchant',
        scopeId: 'brand-new-merchant',
        currency: 'USD',
        amount: '100.00',
      );
      final saved = await finance.manageBudgets!.save(budget);
      expect(saved, isA<ApplicationSuccess<bool>>());
      final listed = await finance.manageBudgets!.list();
      expect(listed, isA<ApplicationSuccess<List<Budget>>>());
      final budgets = (listed as ApplicationSuccess<List<Budget>>).value;
      expect(budgets, hasLength(1));

      final result = await finance.calculateCanonicalBudgetActuals(
        month: DateTime(2026, 10),
        budgets: budgets,
      );

      expect(result, isA<ApplicationSuccess<CanonicalBudgetActuals>>());
      final amounts = (result as ApplicationSuccess<CanonicalBudgetActuals>)
          .value
          .byBudgetId;
      expect(amounts[budget.id], DecimalValue.parse('0'));
    },
  );

  test('missing user preferences never masquerades as zero spending', () async {
    const budget = Budget(
      id: 'merchant-budget',
      scope: 'merchant',
      scopeId: 'brand-new-merchant',
      currency: 'USD',
      amount: '100.00',
    );
    final result = await finance.calculateCanonicalBudgetActuals(
      month: DateTime(2026, 10),
      budgets: [budget],
    );
    expect(result, isA<ApplicationFailure<CanonicalBudgetActuals>>());
  });
}
