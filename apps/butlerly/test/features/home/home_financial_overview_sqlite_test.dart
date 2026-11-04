import 'dart:io';

import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late LocalDatabase database;
  late FinanceServices finance;

  setUp(() async {
    await services.reset();
    directory = await Directory.systemTemp.createTemp(
      'butlerly-home-financial-overview-',
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

    await finance.saveUserPreference(
      UserPreference(
        locale: 'en',
        baseCurrency: CurrencyCode('USD'),
        timeZoneId: 'UTC',
        firstUseCompleted: true,
      ),
    );
  });

  tearDown(() async {
    await services.reset();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'Home retries missing bundled rules and restores all summary/trend values',
    () async {
      await finance.createTransaction(
        CreateTransactionCommand(
          id: 'home-sqlite-expense',
          provenanceId: 'home-sqlite-expense-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 9, 1, 12)),
          transactionDate: '2026-09-01',
          money: Money(
            amount: DecimalValue.parse('12.34'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
        ),
      );

      final result = await finance.loadHomeOverview(
        instant: DateTime.utc(2026, 9, 16, 12),
        trendMonthCount: 3,
      );

      expect(result, isA<ApplicationSuccess<HomeOverview>>());
      final overview = (result as ApplicationSuccess<HomeOverview>).value;
      expect(overview.status, HomeOverviewStatus.available);
      expect(overview.analysisUnavailable, isFalse);
      expect(overview.monthlyTrendUnavailable, isFalse);
      expect(overview.analysis?.spending?.value, DecimalValue.parse('12.34'));
      expect(
        overview.analysis?.spending?.availability,
        AnalysisDataAvailability.sufficient,
      );
      expect(
        overview.analysis?.income?.availability,
        AnalysisDataAvailability.empty,
      );
      expect(
        overview.analysis?.transactionCount?.value,
        DecimalValue.parse('1'),
      );
      expect(overview.analysis?.net?.value, DecimalValue.parse('-12.34'));
      expect(overview.monthlyTrend, hasLength(3));
      expect(
        overview.monthlyTrend.last.spending?.value,
        DecimalValue.parse('12.34'),
      );
    },
  );

  test(
    'new current month recalculates after adding the first transaction',
    () async {
      final empty = await finance.loadHomeOverview(
        instant: DateTime.utc(2026, 11, 1, 12),
        trendMonthCount: 3,
      );
      final emptyOverview = (empty as ApplicationSuccess<HomeOverview>).value;
      expect(emptyOverview.analysisUnavailable, isFalse);
      expect(emptyOverview.monthlyTrendUnavailable, isFalse);

      final created = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'home-sqlite-new-month-expense',
          provenanceId: 'home-sqlite-new-month-expense-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 11, 1, 12)),
          transactionDate: '2026-11-01',
          money: Money(
            amount: DecimalValue.parse('12.34'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          description: 'New month expense',
        ),
      );
      expect(created, isA<ApplicationSuccess<TransactionDto>>());

      final refreshed = await finance.loadHomeOverview(
        instant: DateTime.utc(2026, 11, 1, 12),
        trendMonthCount: 3,
      );
      final overview = (refreshed as ApplicationSuccess<HomeOverview>).value;
      expect(overview.analysisUnavailable, isFalse);
      expect(overview.analysis?.spending?.value, DecimalValue.parse('12.34'));
      expect(
        overview.analysis?.transactionCount?.value,
        DecimalValue.parse('1'),
      );
      expect(overview.analysis?.net?.value, DecimalValue.parse('-12.34'));
      expect(overview.monthlyTrendUnavailable, isFalse);
      expect(
        overview.monthlyTrend.last.spending?.value,
        DecimalValue.parse('12.34'),
      );
    },
  );

  test(
    'Home restores the bundled category definition when a custom category rule is active',
    () async {
      final rules = SqliteAnalysisRuleRepository(database.persistenceDatabase);

      final bundled = await rootBundle.loadString(
        'assets/analysis_rules/metrics/ANL-R010.yaml',
      );
      final custom = bundled
          .replaceFirst('ruleId: ANL-R010', 'ruleId: ANL-R990')
          .replaceFirst('ruleVersion: "1.1.0"', 'ruleVersion: "1.0.0"');
      final parsed = const RestrictedRuleParser().parse(custom);
      final validation = const RuleDefinitionValidator().validate(
        parsed.document!,
      );
      final customDefinition = validation.definition!;
      await database.database.delete(
        'analysis_rule_definitions',
        where: 'rule_id = ?',
        whereArgs: ['ANL-R010'],
      );
      await database.database.delete(
        'analysis_rule_provenance',
        where: 'rule_id = ?',
        whereArgs: ['ANL-R010'],
      );
      await database.database.delete(
        'analysis_rule_activations',
        where: 'rule_id = ?',
        whereArgs: ['ANL-R010'],
      );
      await rules.install(
        customDefinition,
        sourceType: 'user',
        canonicalDefinition: canonicalize(parsed.document!.values),
      );
      await rules.activate(
        customDefinition.identity,
        customDefinition.version,
        true,
        DateTime.utc(2026, 11, 1),
      );

      final result = await finance.loadHomeOverview(
        instant: DateTime.utc(2026, 11, 1, 12),
        trendMonthCount: 3,
      );
      expect(result, isA<ApplicationSuccess<HomeOverview>>());

      final restored = await database.database.query(
        'analysis_rule_definitions',
        where: 'rule_id = ? AND source_type = ?',
        whereArgs: ['ANL-R010', 'bundled'],
      );
      expect(restored, hasLength(1));
      final customActivation = await rules.existingActivation(
        customDefinition.identity,
      );
      expect(customActivation?.version, customDefinition.version);
      expect(customActivation?.enabled, isTrue);
    },
  );
}
