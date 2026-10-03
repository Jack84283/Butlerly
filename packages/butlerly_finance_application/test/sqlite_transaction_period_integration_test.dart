import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'reopens persisted transactions before applying financial timezone bounds',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'butlerly-transaction-period-',
      );
      final path = '${directory.path}/butlerly.db';
      var database = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: await File(
          '../../packages/butlerly_database/database/schema/v1.sql',
        ).readAsString(),
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });

      await database.open();
      final transactions = SqliteTransactionRepository(database);
      final preferences = SqliteUserPreferenceRepository(database);
      await preferences.save(_preference('Asia/Tokyo'));
      final now = DateTime.utc(2026, 10, 2);

      final datedInside = _transaction(
        id: 'dated-inside',
        occurredAt: DateTime.utc(2026, 10, 1, 12),
        transactionDate: '2026-10-01',
        now: now,
      );
      final undatedNewest = _transaction(
        id: 'undated-newest',
        occurredAt: DateTime.utc(2026, 9, 30, 16, 45),
        now: now,
      );
      final legacyBlank = _transaction(
        id: 'legacy-blank',
        occurredAt: DateTime.utc(2026, 9, 30, 16, 30),
        now: now,
      );
      final undatedOutside = _transaction(
        id: 'undated-outside',
        occurredAt: DateTime.utc(2026, 9, 30, 14, 59),
        now: now,
      );
      final archived = _transaction(
        id: 'archived-undated',
        occurredAt: DateTime.utc(2026, 9, 30, 16, 40),
        now: now,
      ).archive(now.add(const Duration(minutes: 1)));

      for (final transaction in [
        datedInside,
        undatedNewest,
        legacyBlank,
        undatedOutside,
        archived,
      ]) {
        await transactions.save(transaction);
      }
      // Simulate a legacy persisted blank date. New writes normalize blanks to
      // NULL, while the query must remain compatible with existing rows.
      await database.connection.update(
        'transactions',
        {'transaction_date': ' '},
        where: 'id = ?',
        whereArgs: [legacyBlank.id.value],
      );
      await database.close();

      database = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: await File(
          '../../packages/butlerly_database/database/schema/v1.sql',
        ).readAsString(),
      );
      await database.open();

      final reopenedTransactions = SqliteTransactionRepository(database);
      final reopenedPreferences = SqliteUserPreferenceRepository(database);
      final tokyoResult =
          await ListTransactions(
            reopenedTransactions,
            preferences: reopenedPreferences,
          )(
            ListTransactionsQuery(
              from: DateTime.utc(2026, 10, 1),
              to: DateTime.utc(2026, 10, 1),
              status: TransactionStatus.active,
              includeUndated: true,
            ),
          );

      expect(tokyoResult, isA<ApplicationSuccess<List<TransactionDto>>>());
      final tokyoValues =
          (tokyoResult as ApplicationSuccess<List<TransactionDto>>).value;
      expect(tokyoValues.map((value) => value.id), [
        datedInside.id.value,
        undatedNewest.id.value,
        legacyBlank.id.value,
      ]);
      expect(tokyoValues.skip(1).map((value) => value.financialDate), [
        DateTime.utc(2026, 10, 1),
        DateTime.utc(2026, 10, 1),
      ]);

      await reopenedPreferences.save(_preference('America/Los_Angeles'));
      final losAngelesResult =
          await ListTransactions(
            reopenedTransactions,
            preferences: reopenedPreferences,
          )(
            ListTransactionsQuery(
              from: DateTime.utc(2026, 9, 30),
              to: DateTime.utc(2026, 9, 30),
              status: TransactionStatus.active,
              includeUndated: true,
            ),
          );

      expect(losAngelesResult, isA<ApplicationSuccess<List<TransactionDto>>>());
      final losAngelesValues =
          (losAngelesResult as ApplicationSuccess<List<TransactionDto>>).value;
      expect(losAngelesValues.map((value) => value.id), [
        undatedNewest.id.value,
        legacyBlank.id.value,
        undatedOutside.id.value,
      ]);
      expect(losAngelesValues.map((value) => value.financialDate), [
        DateTime.utc(2026, 9, 30),
        DateTime.utc(2026, 9, 30),
        DateTime.utc(2026, 9, 30),
      ]);
    },
  );
}

UserPreference _preference(String timeZoneId) => UserPreference(
  locale: 'en',
  baseCurrency: CurrencyCode('USD'),
  timeZoneId: timeZoneId,
);

Transaction _transaction({
  required String id,
  required DateTime occurredAt,
  required DateTime now,
  String? transactionDate,
}) => Transaction(
  id: TransactionId(id),
  timing: KnownTransactionTime(occurredAt),
  money: Money(amount: DecimalValue.parse('10'), currency: CurrencyCode('USD')),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  transactionDate: transactionDate,
  provenance: [
    Provenance(
      id: ProvenanceId('$id-provenance'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: now,
    ),
  ],
  createdAt: now,
  updatedAt: now,
);
