import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'transaction save sound preference persists through SQLite reload',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'butlerly-sound-',
      );
      final path = '${directory.path}/preferences.db';
      final schema = await File('database/schema/v1.sql').readAsString();

      Future<ButlerlyDatabase> open() async {
        final database = ButlerlyDatabase(
          factory: databaseFactoryFfi,
          path: path,
          schemaSql: schema,
        );
        await database.open();
        return database;
      }

      try {
        var database = await open();
        var repository = SqliteUserPreferenceRepository(database);
        await repository.save(
          UserPreference(
            locale: 'en',
            baseCurrency: CurrencyCode('USD'),
            timeZoneId: 'UTC',
            transactionSaveSoundEnabled: false,
          ),
        );
        expect((await repository.load())?.transactionSaveSoundEnabled, isFalse);
        await database.close();

        database = await open();
        repository = SqliteUserPreferenceRepository(database);
        expect((await repository.load())?.transactionSaveSoundEnabled, isFalse);
        await database.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
