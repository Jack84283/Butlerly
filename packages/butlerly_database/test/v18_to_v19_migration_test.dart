import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/deployment_sql.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v18 to v19 creates financial profile storage', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-v19-');
    final path = '${directory.path}/legacy.db';
    final current = await File('database/schema/v1.sql').readAsString();
    final tableStart = current.indexOf('CREATE TABLE financial_profiles (');
    final tableEnd = current.indexOf(');', tableStart) + 2;
    final legacy = current.replaceRange(tableStart, tableEnd, '');
    try {
      final old = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: legacy,
        targetVersion: 18,
      );
      await old.open();
      expect(
        await old.connection.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'financial_profiles'",
        ),
        isEmpty,
      );
      await old.close();

      final upgraded = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: legacy,
        targetVersion: 19,
        migrations: {19: await migrationSqlForVersion(19)},
      );
      await upgraded.open();
      addTearDown(upgraded.close);

      expect(await upgraded.connection.getVersion(), 19);
      expect(
        await upgraded.connection.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'financial_profiles'",
        ),
        hasLength(1),
      );
    } finally {
      await Directory(directory.path).delete(recursive: true);
    }
  });
}
