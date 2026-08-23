import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_database/src/database/schema.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
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

  test('applies current schema with foreign keys and indexes', () async {
    final version = await database.connection.getVersion();
    final foreignKeys = await database.connection.rawQuery(
      'PRAGMA foreign_keys',
    );
    final tables = await database.connection.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );

    expect(version, Schema.version);
    expect(foreignKeys.single.values.single, 1);
    expect(
      tables.map((row) => row['name']),
      containsAll([
        'transactions',
        'provenances',
        'evidence_items',
        'suggestions',
        'review_issues',
        'user_preferences',
        'category_translations',
        'tag_translations',
        'reference_data',
        'reference_data_translations',
      ]),
    );
    expect(await database.passesIntegrityCheck(), isTrue);
  });

  test('persists the single local user preference record', () async {
    final repository = SqliteUserPreferenceRepository(database);
    expect(await repository.load(), isNull);

    await repository.save(
      UserPreference(
        locale: 'zh',
        formattingLocale: 'zh-Hans-CN',
        regionCode: 'CN',
        baseCurrency: CurrencyCode('CNY'),
        timeZoneId: 'Asia/Shanghai',
        externalAiEnabled: true,
        firstUseCompleted: true,
      ),
    );

    final value = await repository.load();
    expect(value?.locale, 'zh');
    expect(value?.formattingLocale, 'zh-Hans-CN');
    expect(value?.regionCode, 'CN');
    expect(value?.baseCurrency.value, 'CNY');
    expect(value?.timeZoneId, 'Asia/Shanghai');
    expect(value?.externalAiEnabled, isTrue);
    expect(value?.firstUseCompleted, isTrue);
  });

  test('migrates a v1 UTC instant to v2 business-date fields', () async {
    const path = 'butlerly-v1-to-v2-test.db';
    await databaseFactoryFfi.deleteDatabase(path);
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          for (final statement in Schema.migration1) {
            await db.execute(statement);
          }
        },
      ),
    );
    await legacy.insert('provenances', {
      'id': 'p1',
      'source_type': 'userEntry',
      'captured_at': '2026-08-10T00:00:00.000Z',
    });
    await legacy.insert('transactions', {
      'id': 't1',
      'occurred_at': '2026-08-10T01:30:00-07:00',
      'amount_coefficient': '1',
      'amount_scale': 0,
      'currency': 'USD',
      'direction': 'expense',
      'source_type': 'manual',
      'status': 'active',
      'created_at': '2026-08-10T00:00:00.000Z',
      'updated_at': '2026-08-10T00:00:00.000Z',
    });
    await legacy.close();

    final migrated = ButlerlyDatabase(factory: databaseFactoryFfi, path: path);
    await migrated.open();
    final row = (await migrated.connection.query('transactions')).single;
    expect(row['occurred_at_utc'], '2026-08-10T08:30:00.000Z');
    expect(row['transaction_date'], '2026-08-10');
    expect(row['time_zone_id'], isNull);
    await migrated.close();
    await databaseFactoryFfi.deleteDatabase(path);
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
