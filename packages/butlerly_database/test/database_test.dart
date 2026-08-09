import 'package:butlerly_database/butlerly_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  late ButlerlyDatabase database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await database.open();
  });

  tearDown(() => database.close());

  test('applies migration 1 with foreign keys and indexes', () async {
    final version = await database.connection.getVersion();
    final foreignKeys = await database.connection.rawQuery(
      'PRAGMA foreign_keys',
    );
    final tables = await database.connection.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );

    expect(version, 1);
    expect(foreignKeys.single.values.single, 1);
    expect(
      tables.map((row) => row['name']),
      containsAll([
        'transactions',
        'provenances',
        'evidence_items',
        'suggestions',
        'review_issues',
      ]),
    );
    expect(await database.passesIntegrityCheck(), isTrue);
  });

  test('rolls back an atomic transaction on failure', () async {
    await expectLater(
      database.transaction((executor) async {
        await executor.insert('merchants', {
          'id': 'merchant-1',
          'name': 'Valid',
        });
        await executor.insert('merchants', {'id': 'merchant-2', 'name': null});
      }),
      throwsA(anything),
    );

    expect(await database.connection.query('merchants'), isEmpty);
  });

  test(
    'prepares only an integrity-checked consistent backup boundary',
    () async {
      await database.prepareForConsistentBackup();
      expect(await database.passesIntegrityCheck(), isTrue);
    },
  );
}
