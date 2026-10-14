import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('local display name persists in fresh preferences database', () async {
    final schema = await File('database/schema/v1.sql').readAsString();
    final database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: schema,
    );
    await database.open();
    final repository = SqliteUserPreferenceRepository(database);
    await repository.save(
      UserPreference(
        locale: 'en',
        baseCurrency: CurrencyCode('USD'),
        timeZoneId: 'UTC',
        displayName: 'Mia',
      ),
    );
    expect((await repository.load())?.displayName, 'Mia');
    await database.close();
  });

  test('v14 preferences upgrade to v15 with empty display name', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-name-');
    final path = '${directory.path}/preferences.db';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 14,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE user_preferences ('
            'id INTEGER PRIMARY KEY NOT NULL, '
            'locale TEXT NOT NULL, '
            'base_currency TEXT NOT NULL, '
            'time_zone_id TEXT NOT NULL, '
            'external_ai_enabled INTEGER NOT NULL, '
            'first_use_completed INTEGER NOT NULL, '
            'appearance TEXT NOT NULL, '
            'color_theme TEXT NOT NULL, '
            'updated_at TEXT NOT NULL)',
          );
          await db.insert('user_preferences', {
            'id': 1,
            'locale': 'en',
            'base_currency': 'USD',
            'time_zone_id': 'UTC',
            'external_ai_enabled': 0,
            'first_use_completed': 1,
            'appearance': 'dark',
            'color_theme': 'butlerRed',
            'updated_at': '',
          });
        },
      ),
    );
    await old.close();

    final schema = await File('database/schema/v1.sql').readAsString();
    final deployment = await File(
      'database/migrations/deployment.sql',
    ).readAsString();
    final database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: path,
      schemaSql: schema,
      migrations: parseDeploymentMigrations(deployment),
    );
    try {
      await database.open();
      final repository = SqliteUserPreferenceRepository(database);
      expect(await database.connection.getVersion(), 15);
      expect((await repository.load())?.displayName, '');
      await repository.save(
        UserPreference(
          locale: 'en',
          baseCurrency: CurrencyCode('USD'),
          timeZoneId: 'UTC',
          displayName: 'Jack',
        ),
      );
      expect((await repository.load())?.displayName, 'Jack');
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
