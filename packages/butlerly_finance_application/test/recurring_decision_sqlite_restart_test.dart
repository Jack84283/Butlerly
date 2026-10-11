import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'recurring decisions survive SQLite close and reopen without restoring an ineligible forecast',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'butlerly-recurring-restart-',
      );
      final path = '${directory.path}/butlerly.db';
      final schema = await File(
        '../butlerly_database/database/schema/v1.sql',
      ).readAsString();
      ButlerlyDatabase? database;
      try {
        database = ButlerlyDatabase(
          factory: databaseFactoryFfi,
          path: path,
          schemaSql: schema,
        );
        await database.open();
        final transactions = SqliteTransactionRepository(database);
        final preferences = SqliteUserPreferenceRepository(database);
        final decisions = SqliteRecurringPatternDecisionRepository(database);
        await preferences.save(_preference());
        for (final transaction in [
          _transaction('one', '2026-01-01', '10'),
          _transaction('two', '2026-02-01', '10'),
          _transaction('three', '2026-03-01', '20'),
        ]) {
          await transactions.save(transaction);
        }

        final detected = await DetectRecurringPatterns(
          transactions,
          preferences: preferences,
          decisions: decisions,
        )(timeZoneId: 'UTC');
        final pattern = (detected as ApplicationSuccess<List<RecurringPattern>>)
            .value
            .single;
        expect(pattern.expectedNextDate, isNull);
        final saved = await SaveRecurringPatternDecision(
          decisions,
          _Clock(DateTime.utc(2026, 3, 2)),
        ).confirm(pattern);
        expect(saved, isA<ApplicationSuccess<RecurringPattern>>());
        await database.close();

        database = ButlerlyDatabase(
          factory: databaseFactoryFfi,
          path: path,
          schemaSql: schema,
        );
        await database.open();
        final reopenedTransactions = SqliteTransactionRepository(database);
        final reopenedPreferences = SqliteUserPreferenceRepository(database);
        final reopenedDecisions = SqliteRecurringPatternDecisionRepository(
          database,
        );
        final reopened = await DetectRecurringPatterns(
          reopenedTransactions,
          preferences: reopenedPreferences,
          decisions: reopenedDecisions,
        )(timeZoneId: 'UTC');
        final restored =
            (reopened as ApplicationSuccess<List<RecurringPattern>>)
                .value
                .single;
        expect(restored.status, RecurringPatternStatus.confirmed);
        expect(restored.cadence, RecurringCadence.monthly);
        expect(restored.expectedAmount, pattern.expectedAmount);
        expect(restored.expectedNextDate, isNull);
      } finally {
        await database?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

UserPreference _preference() => UserPreference(
  locale: 'en',
  baseCurrency: CurrencyCode('USD'),
  timeZoneId: 'UTC',
);

Transaction _transaction(String id, String date, String amount) {
  final instant = DateTime.parse('${date}T12:00:00Z');
  return Transaction(
    id: TransactionId(id),
    timing: KnownTransactionTime(instant),
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
    sourceType: TransactionSourceType.import,
    provenance: [
      Provenance(
        id: ProvenanceId('$id-provenance'),
        sourceType: ProvenanceSourceType.import,
        capturedAt: instant,
        originalRepresentation: 'Variable Bill $amount',
      ),
    ],
    transactionDate: date,
    description: 'Variable Bill',
    createdAt: instant,
    updatedAt: instant,
  );
}

final class _Clock implements ApplicationClock {
  const _Clock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
