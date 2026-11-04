import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/deployment_sql.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v20 to v21 creates report and operation diagnostic storage', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-v21-');
    final path = '${directory.path}/legacy.db';
    var legacy = await File('database/schema/v1.sql').readAsString();
    for (final marker in const [
      'CREATE TABLE data_integrity_reports',
      'CREATE TABLE data_integrity_findings',
      'CREATE INDEX idx_data_integrity_findings_report',
      'CREATE TABLE operation_diagnostics',
      'CREATE INDEX idx_operation_diagnostics_detected_at',
    ]) {
      final start = legacy.indexOf(marker);
      expect(start, greaterThanOrEqualTo(0), reason: marker);
      final end = legacy.indexOf(';', start) + 1;
      legacy = legacy.replaceRange(start, end, '');
    }
    try {
      final old = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: legacy,
        targetVersion: 20,
      );
      await old.open();
      expect(
        await old.connection.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('data_integrity_reports', 'operation_diagnostics')",
        ),
        isEmpty,
      );
      await old.close();

      final upgraded = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: legacy,
        targetVersion: 21,
        migrations: {21: await migrationSqlForVersion(21)},
      );
      await upgraded.open();
      addTearDown(upgraded.close);

      expect(
        await upgraded.connection.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('data_integrity_reports', 'operation_diagnostics') "
          'ORDER BY name',
        ),
        containsAllInOrder(<Map<String, Object?>>[
          {'name': 'data_integrity_reports'},
          {'name': 'operation_diagnostics'},
        ]),
      );
    } finally {
      await Directory(directory.path).delete(recursive: true);
    }
  });
}
