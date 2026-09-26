import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'v10 to v11 adds matching tables without resetting existing data',
    () async {
      final directory = await Directory.systemTemp.createTemp('butlerly-v11-');
      final databasePath = '${directory.path}/legacy.db';
      final currentSchema = await File('database/schema/v1.sql').readAsString();
      final legacySchema = splitSqlStatements(currentSchema)
          .where(
            (statement) =>
                !statement.startsWith('CREATE TABLE merchant_aliases') &&
                !statement.startsWith(
                  'CREATE TABLE merchant_normalization_patterns',
                ) &&
                !statement.startsWith('CREATE TABLE transaction_rules') &&
                !statement.startsWith(
                  'CREATE INDEX idx_merchant_aliases_merchant',
                ) &&
                !statement.startsWith(
                  'CREATE INDEX idx_merchant_patterns_merchant',
                ) &&
                !statement.startsWith(
                  'CREATE INDEX idx_transaction_rules_priority',
                ),
          )
          .join(';${String.fromCharCode(10)}');
      final migration = await File(
        'database/migrations/v10_to_v11.sql',
      ).readAsString();

      try {
        final legacy = ButlerlyDatabase(
          factory: databaseFactoryFfi,
          path: databasePath,
          schemaSql: legacySchema,
          targetVersion: 10,
        );
        await legacy.open();
        await legacy.connection.insert('merchants', {
          'id': 'merchant.legacy',
          'name': 'Legacy merchant',
          'status': 'active',
          'normalized_name': 'legacy merchant',
        });
        await legacy.close();

        final upgraded = ButlerlyDatabase(
          factory: databaseFactoryFfi,
          path: databasePath,
          schemaSql: currentSchema,
          targetVersion: 11,
          migrations: {11: migration},
        );
        await upgraded.open();
        addTearDown(upgraded.close);

        expect(await upgraded.connection.getVersion(), 11);
        expect(
          await upgraded.connection.query(
            'merchants',
            columns: ['name'],
            where: 'id = ?',
            whereArgs: ['merchant.legacy'],
          ),
          [
            <String, Object?>{'name': 'Legacy merchant'},
          ],
        );
        for (final table in [
          'merchant_aliases',
          'merchant_normalization_patterns',
          'transaction_rules',
        ]) {
          expect(
            await upgraded.connection.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
              [table],
            ),
            hasLength(1),
          );
        }
        expect(await upgraded.passesIntegrityCheck(), isTrue);
      } finally {
        await Directory(directory.path).delete(recursive: true);
      }
    },
  );
}
