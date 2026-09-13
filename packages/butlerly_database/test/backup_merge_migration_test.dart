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

  test('v8 migration adds merge metadata and transaction tombstones', () async {
    final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);
    final baseline = await File('database/schema/v1.sql').readAsString();
    for (final statement in splitSqlStatements(baseline)) {
      await database.execute(statement);
    }
    final migration = await File(
      'database/migrations/v7_to_v8.sql',
    ).readAsString();
    for (final statement in splitSqlStatements(migration)) {
      await database.execute(statement);
    }

    final merchantColumns = await database.rawQuery('PRAGMA table_info(merchants)');
    expect(merchantColumns.map((row) => row['name']), containsAll(['created_at', 'updated_at']));
    final tombstoneTable = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'entity_tombstones'",
    );
    expect(tombstoneTable, hasLength(1));

    await database.insert('transactions', {
      'id': 'transaction-delete-me',
      'unknown_time_reason': 'unknown',
      'amount_coefficient': '100',
      'amount_scale': 2,
      'currency': 'USD',
      'direction': 'expense',
      'source_type': 'manual',
      'status': 'active',
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
    expect(DateTime.tryParse(tombstones.single['deleted_at']! as String), isNotNull);
  });
}
