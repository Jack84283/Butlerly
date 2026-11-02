import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/deployment_sql.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v19 to v20 preserves analysis-rule source provenance', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-v20-');
    final path = '${directory.path}/legacy.db';
    final current = await File('database/schema/v1.sql').readAsString();
    final tableStart = current.indexOf(
      'CREATE TABLE analysis_rule_provenance (',
    );
    final tableEnd = current.indexOf(');', tableStart) + 2;
    final legacy = current.replaceRange(tableStart, tableEnd, '');
    try {
      final old = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: legacy,
        targetVersion: 19,
      );
      await old.open();
      await old.connection.insert('analysis_rule_definitions', {
        'rule_id': 'ANL-R010',
        'rule_version': '1.1.0',
        'schema_version': '1.0.0',
        'source_type': 'bundled',
        'definition': '{}',
        'canonical_definition': '{}',
        'definition_hash': 'a' * 64,
        'validation_status': 'valid',
        'validation_diagnostics': null,
        'installed_at': '2026-11-01T00:00:00.000Z',
        'retired_at': null,
      });
      await old.close();

      final upgraded = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: legacy,
        targetVersion: 20,
        migrations: {20: await migrationSqlForVersion(20)},
      );
      await upgraded.open();
      addTearDown(upgraded.close);

      expect(
        await upgraded.connection.query('analysis_rule_provenance'),
        contains(
          allOf(
            containsPair('rule_id', 'ANL-R010'),
            containsPair('rule_version', '1.1.0'),
            containsPair('source_type', 'bundled'),
            containsPair('definition_hash', 'a' * 64),
            containsPair('recorded_at', '2026-11-01T00:00:00.000Z'),
          ),
        ),
      );
    } finally {
      await Directory(directory.path).delete(recursive: true);
    }
  });
}
