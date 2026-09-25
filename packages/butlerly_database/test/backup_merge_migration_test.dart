import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('SQL splitter preserves trigger bodies as one statement', () {
    const sql = '''
CREATE TABLE sample(id TEXT PRIMARY KEY, updated_at TEXT);
CREATE TRIGGER sample_touch AFTER UPDATE ON sample
BEGIN
  UPDATE sample SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;
CREATE INDEX idx_sample_updated ON sample(updated_at);
''';

    final statements = splitSqlStatements(sql);

    expect(statements, hasLength(3));
    expect(statements[1], startsWith('CREATE TRIGGER sample_touch'));
    expect(statements[1], contains('WHERE id = NEW.id;'));
    expect(statements[1], endsWith('END'));
  });

  test('v8 migration adds merge metadata and tombstones to v7 tables', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);

    const v7Fixture = '''
CREATE TABLE payment_sources(id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, status TEXT NOT NULL);
CREATE TABLE merchants(id TEXT PRIMARY KEY, name TEXT NOT NULL, is_built_in INTEGER NOT NULL DEFAULT 0);
CREATE TABLE categories(id TEXT PRIMARY KEY, name TEXT NOT NULL, origin TEXT NOT NULL);
CREATE TABLE tags(id TEXT PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE transactions(id TEXT PRIMARY KEY, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE transaction_tags(transaction_id TEXT NOT NULL, tag_id TEXT NOT NULL, PRIMARY KEY(transaction_id, tag_id));
CREATE TABLE user_preferences(id INTEGER PRIMARY KEY NOT NULL, locale TEXT NOT NULL);
CREATE TABLE evidence_items(id TEXT PRIMARY KEY);
CREATE TABLE attachment_links(id TEXT PRIMARY KEY);
CREATE TABLE reconciliation_links(id TEXT PRIMARY KEY);
''';
    for (final statement in splitSqlStatements(v7Fixture)) {
      await database.execute(statement);
    }

    final migration = await File(
      'database/migrations/v7_to_v8.sql',
    ).readAsString();
    for (final statement in splitSqlStatements(migration)) {
      await database.execute(statement);
    }

    final merchantColumns = await database.rawQuery(
      'PRAGMA table_info(merchants)',
    );
    expect(
      merchantColumns.map((row) => row['name']),
      containsAll(['created_at', 'updated_at']),
    );
    final transactionTagColumns = await database.rawQuery(
      'PRAGMA table_info(transaction_tags)',
    );
    expect(
      transactionTagColumns.map((row) => row['name']),
      contains('created_at'),
    );
    final tombstoneTable = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'entity_tombstones'",
    );
    expect(tombstoneTable, hasLength(1));

    await database.insert('transactions', {
      'id': 'transaction-delete-me',
      'created_at': '2026-09-12T10:00:00.000Z',
      'updated_at': '2026-09-12T10:00:00.000Z',
    });
    await database.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: ['transaction-delete-me'],
    );

    final tombstones = await database.query(
      'entity_tombstones',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['transactions', 'transaction-delete-me'],
    );
    expect(tombstones, hasLength(1));
    expect(
      DateTime.tryParse(tombstones.single['deleted_at']! as String),
      isNotNull,
    );
  });

  test(
    'v10 migration moves payment facts into settlements and removes legacy transfers',
    () async {
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      addTearDown(database.close);

      const v9Fixture = '''
CREATE TABLE entity_tombstones(
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  deleted_at TEXT NOT NULL,
  PRIMARY KEY(entity_type, entity_id)
);
CREATE TABLE payment_sources(
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  status TEXT NOT NULL
);
CREATE TABLE transactions(
  id TEXT PRIMARY KEY,
  amount_coefficient TEXT NOT NULL,
  amount_scale INTEGER NOT NULL,
  currency TEXT NOT NULL,
  direction TEXT NOT NULL,
  status TEXT NOT NULL,
  payment_source_id TEXT,
  transaction_date TEXT,
  description TEXT,
  external_reference TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE payment_settlements(
  id TEXT PRIMARY KEY,
  settlement_transaction_id TEXT NOT NULL UNIQUE REFERENCES transactions(id) ON DELETE CASCADE,
  payment_source_id TEXT NOT NULL REFERENCES payment_sources(id),
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  statement_balance_coefficient TEXT,
  statement_balance_scale INTEGER,
  statement_balance_currency TEXT,
  status TEXT NOT NULL,
  description TEXT,
  external_reference TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''';
      for (final statement in splitSqlStatements(v9Fixture)) {
        await database.execute(statement);
      }
      await database.execute('PRAGMA foreign_keys = ON');
      await database.insert('payment_sources', {
        'id': 'visa',
        'name': 'Visa',
        'type': 'card',
        'status': 'active',
      });
      await database.insert('transactions', {
        'id': 'legacy-payment',
        'amount_coefficient': '284672',
        'amount_scale': 2,
        'currency': 'USD',
        'direction': 'transfer',
        'status': 'active',
        'payment_source_id': 'visa',
        'transaction_date': '2026-09-20',
        'created_at': '2026-09-20T12:00:00.000Z',
        'updated_at': '2026-09-20T12:00:00.000Z',
      });
      await database.insert('payment_settlements', {
        'id': 'settlement-1',
        'settlement_transaction_id': 'legacy-payment',
        'payment_source_id': 'visa',
        'period_start': '2026-08-15',
        'period_end': '2026-09-14',
        'statement_balance_coefficient': '284672',
        'statement_balance_scale': 2,
        'statement_balance_currency': 'USD',
        'status': 'open',
        'created_at': '2026-09-20T12:00:00.000Z',
        'updated_at': '2026-09-20T12:00:00.000Z',
      });

      final migration = await File(
        'database/migrations/v9_to_v10.sql',
      ).readAsString();
      for (final statement in splitSqlStatements(migration)) {
        await database.execute(statement);
      }

      final settlement = (await database.query('payment_settlements')).single;
      expect(settlement['payment_amount_coefficient'], '284672');
      expect(settlement['payment_amount_scale'], 2);
      expect(settlement['payment_currency'], 'USD');
      expect(settlement['payment_date'], '2026-09-20');
      expect(settlement.containsKey('settlement_transaction_id'), isFalse);
      expect(
        await database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['legacy-payment'],
        ),
        isEmpty,
      );
      expect(
        await database.query(
          'entity_tombstones',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: ['transactions', 'legacy-payment'],
        ),
        isEmpty,
      );
    },
  );

  test('current baseline creates v8 merge metadata directly', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final baseline = await File('database/schema/v1.sql').readAsString();
    for (final statement in splitSqlStatements(baseline)) {
      await database.execute(statement);
    }

    final categoryColumns = await database.rawQuery(
      'PRAGMA table_info(categories)',
    );
    expect(
      categoryColumns.map((row) => row['name']),
      containsAll(['created_at', 'updated_at']),
    );
    expect(
      await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = 'transactions_tombstone'",
      ),
      hasLength(1),
    );
  });
}
