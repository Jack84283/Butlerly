import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v11 to v12 normalizes valid legacy transaction instants', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-v12-');
    final databasePath = '${directory.path}/legacy.db';
    final schema = await File('database/schema/v1.sql').readAsString();
    final now = DateTime.utc(2026, 10, 1, 12);
    final transaction = Transaction(
      id: TransactionId('migration-offset-transaction'),
      timing: KnownTransactionTime(DateTime.utc(2026, 10, 1, 7, 30)),
      money: Money(
        amount: DecimalValue.parse('10'),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.manual,
      provenance: [
        Provenance(
          id: ProvenanceId('migration-offset-provenance'),
          sourceType: ProvenanceSourceType.userEntry,
          capturedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    try {
      final legacy = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: databasePath,
        schemaSql: schema,
        targetVersion: 11,
      );
      await legacy.open();
      await SqliteTransactionRepository(legacy).save(transaction);
      await legacy.connection.update(
        'transactions',
        {
          'occurred_at': '2026-10-01T00:30:00.000-07:00',
          'occurred_at_utc': '2026-10-01T00:30:00.000-07:00',
        },
        where: 'id = ?',
        whereArgs: [transaction.id.value],
      );
      await legacy.close();

      final migration = await File(
        'database/migrations/v11_to_v12.sql',
      ).readAsString();
      final upgraded = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: databasePath,
        schemaSql: schema,
        targetVersion: 12,
        migrations: {12: migration},
      );
      await upgraded.open();
      addTearDown(upgraded.close);

      expect(await upgraded.connection.getVersion(), 12);
      await upgraded.close();
      await upgraded.open();
      final persisted = await SqliteTransactionRepository(upgraded).query(
        TransactionRepositoryQuery(
          from: DateTime.utc(2026, 10, 1),
          to: DateTime.utc(2026, 10, 1),
          occurredAtFrom: DateTime.utc(2026, 10, 1, 7, 30),
          occurredAtToExclusive: DateTime.utc(2026, 10, 1, 8),
        ),
      );
      expect(persisted.map((value) => value.id), [transaction.id]);
      expect(
        (await upgraded.connection.query(
          'transactions',
          columns: ['occurred_at', 'occurred_at_utc'],
          where: 'id = ?',
          whereArgs: [transaction.id.value],
        )).single,
        {
          'occurred_at': '2026-10-01T07:30:00.000Z',
          'occurred_at_utc': '2026-10-01T07:30:00.000Z',
        },
      );
    } finally {
      await Directory(directory.path).delete(recursive: true);
    }
  });

  test('v11 to v12 makes malformed legacy instants safely unknown', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-v12-');
    final databasePath = '${directory.path}/legacy-malformed.db';
    final schema = await File('database/schema/v1.sql').readAsString();
    final now = DateTime.utc(2026, 10, 1, 12);
    final transaction = Transaction(
      id: TransactionId('migration-malformed-transaction'),
      timing: const UnknownTransactionTime(
        UnknownTransactionTimeReason.pending,
      ),
      money: Money(
        amount: DecimalValue.parse('10'),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.manual,
      provenance: [
        Provenance(
          id: ProvenanceId('migration-malformed-provenance'),
          sourceType: ProvenanceSourceType.userEntry,
          capturedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    try {
      final legacy = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: databasePath,
        schemaSql: schema,
        targetVersion: 11,
      );
      await legacy.open();
      await SqliteTransactionRepository(legacy).save(transaction);
      await legacy.connection.update(
        'transactions',
        {
          'occurred_at': 'not-a-timestamp',
          'occurred_at_utc': 'also-not-a-timestamp',
          'unknown_time_reason': null,
        },
        where: 'id = ?',
        whereArgs: [transaction.id.value],
      );
      await legacy.close();

      final migration = await File(
        'database/migrations/v11_to_v12.sql',
      ).readAsString();
      final upgraded = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: databasePath,
        schemaSql: schema,
        targetVersion: 12,
        migrations: {12: migration},
      );
      await upgraded.open();
      addTearDown(upgraded.close);

      expect(
        (await upgraded.connection.query(
          'transactions',
          columns: ['occurred_at', 'occurred_at_utc', 'unknown_time_reason'],
          where: 'id = ?',
          whereArgs: [transaction.id.value],
        )).single,
        {
          'occurred_at': null,
          'occurred_at_utc': null,
          'unknown_time_reason': 'unknown',
        },
      );
      final restored = await SqliteTransactionRepository(
        upgraded,
      ).findById(transaction.id);
      expect(restored?.timing, isA<UnknownTransactionTime>());
      expect(
        (restored!.timing as UnknownTransactionTime).reason,
        UnknownTransactionTimeReason.unknown,
      );
    } finally {
      await Directory(directory.path).delete(recursive: true);
    }
  });
}
