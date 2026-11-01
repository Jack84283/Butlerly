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
    await SqliteTransactionRepository(
      database.persistenceDatabase,
    ).save(_expense());
  });

  tearDown(() async {
    await services.reset();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'Home retries missing bundled rules and restores all summary/trend values',
    () async {
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
}

Transaction _expense() {
  final at = DateTime.utc(2026, 9, 1, 12);
  return Transaction(
    id: TransactionId('home-sqlite-expense'),
    timing: KnownTransactionTime(at),
    transactionDate: '2026-09-01',
    money: Money(
      amount: DecimalValue.parse('12.34'),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
    sourceType: TransactionSourceType.manual,
    provenance: [
      Provenance(
        id: ProvenanceId('home-sqlite-expense-provenance'),
        sourceType: ProvenanceSourceType.userEntry,
        capturedAt: at,
      ),
    ],
    createdAt: at,
    updatedAt: at,
  );
}
