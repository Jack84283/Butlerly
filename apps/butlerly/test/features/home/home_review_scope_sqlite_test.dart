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
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late LocalDatabase database;
  late FinanceServices finance;

  setUp(() async {
    await services.reset();
    directory = await Directory.systemTemp.createTemp('butlerly-home-review-');
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
    'scoped Review uses SQLite period filtering for review transactions',
    () async {
      await _saveReviewTransaction(
        database,
        id: 'sqlite-review-in-period',
        description: 'SQLite in-period review',
        date: '2026-09-05',
      );
      await _saveReviewTransaction(
        database,
        id: 'sqlite-review-outside-period',
        description: 'SQLite outside-period review',
        date: '2026-08-05',
      );
      final result = await finance.listReviewItems(
        ListReviewItemsQuery(
          scope: ReviewPeriodScope.fromDateValues(
            startDate: '2026-09-01',
            endDate: '2026-09-16',
            timeZoneId: 'UTC',
          ),
        ),
      );
      expect(result, isA<ApplicationSuccess<List<ReviewItemDto>>>());
      final items = (result as ApplicationSuccess<List<ReviewItemDto>>).value;
      expect(items.map((value) => value.transactionId), [
        'sqlite-review-in-period',
      ]);
    },
  );

  test(
    'scoped Review applies timezone DST boundaries to undated occurrences',
    () async {
      await _saveReviewTransaction(
        database,
        id: 'sqlite-review-dst-start',
        description: 'SQLite DST period start',
        occurredAt: DateTime.utc(2026, 3, 8, 8),
      );
      await _saveReviewTransaction(
        database,
        id: 'sqlite-review-dst-end',
        description: 'SQLite DST period end',
        occurredAt: DateTime.utc(2026, 3, 9, 6, 59, 59),
      );
      await _saveReviewTransaction(
        database,
        id: 'sqlite-review-dst-outside',
        description: 'SQLite after DST period',
        occurredAt: DateTime.utc(2026, 3, 9, 7),
      );

      final result = await finance.listReviewItems(
        ListReviewItemsQuery(
          scope: ReviewPeriodScope.fromDateValues(
            startDate: '2026-03-08',
            endDate: '2026-03-08',
            timeZoneId: 'America/Los_Angeles',
          ),
        ),
      );
      expect(result, isA<ApplicationSuccess<List<ReviewItemDto>>>());
      final items = (result as ApplicationSuccess<List<ReviewItemDto>>).value;
      expect(items, hasLength(2));
      expect(
        items.map((value) => value.transactionId).toSet(),
        equals({'sqlite-review-dst-start', 'sqlite-review-dst-end'}),
      );
    },
  );
}

Future<void> _saveReviewTransaction(
  LocalDatabase database, {
  required String id,
  required String description,
  String? date,
  DateTime? occurredAt,
}) async {
  final effectiveOccurredAt =
      occurredAt ?? DateTime.parse('${date!}T12:00:00Z');
  final transaction = Transaction(
    id: TransactionId(id),
    timing: KnownTransactionTime(effectiveOccurredAt),
    transactionDate: date,
    money: Money(
      amount: DecimalValue.parse('12.50'),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
    sourceType: TransactionSourceType.manual,
    description: description,
    provenance: [
      Provenance(
        id: ProvenanceId('$id-provenance'),
        sourceType: ProvenanceSourceType.userEntry,
        capturedAt: effectiveOccurredAt,
      ),
    ],
    createdAt: effectiveOccurredAt,
    updatedAt: effectiveOccurredAt,
  );
  final repository = SqliteTransactionRepository(database.persistenceDatabase);
  final updatedAt = effectiveOccurredAt.add(const Duration(seconds: 1));
  await repository.save(
    transaction.addReviewIssue(
      ReviewIssue(
        id: ReviewIssueId('$id-issue'),
        transactionId: TransactionId(id),
        reason: ReviewIssueReason.uncertain,
        createdAt: updatedAt,
      ),
      updatedAt,
    ),
  );
}
