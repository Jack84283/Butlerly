import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('incomplete current-version database fails before catalog seed',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'butlerly-incomplete-install-',
    );
    final dbPath = '${directory.path}/butlerly.db';
    final incomplete = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: ButlerlyDatabase.databaseVersion,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE categories (id TEXT PRIMARY KEY)');
        },
      ),
    );
    await incomplete.close();
    final baseline = await File('database/schema/v1.sql').readAsString();
    final database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: dbPath,
      schemaSql: baseline,
      seedSql: ["INSERT INTO categories (id) VALUES ('test')"],
      validateSchemaBeforeSeed: true,
    );
    try {
      await expectLater(
        database.open(),
        throwsA(
          isA<RepositoryException>().having(
            (error) => error.code,
            'code',
            RepositoryFailureCode.migration,
          ),
        ),
      );
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });

  test('fresh installation uses production baseline, hardening and catalog',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'butlerly-production-install-',
    );
    final dbPath = '${directory.path}/butlerly.db';
    final baseline = await File('database/schema/v1.sql').readAsString();
    final deployment = await File(
      'database/migrations/deployment.sql',
    ).readAsString();
    final catalog = await File('database/seed/catalog.sql').readAsString();
    final db = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: dbPath,
      schemaSql:
          '$baseline\n${baselineHardeningFromDeployment(deployment)}',
      seedSql: [catalog],
      migrations: parseDeploymentMigrations(deployment),
      validateSchemaBeforeSeed: true,
    );
    try {
      await db.open();
      expect(await db.connection.getVersion(), ButlerlyDatabase.databaseVersion);
      for (final table in [
        'categories',
        'category_translations',
        'merchants',
        'duplicate_candidate_groups',
        'transactions',
      ]) {
        expect(
          await db.connection.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            [table],
          ),
          hasLength(1),
          reason: 'Missing expected production table $table',
        );
      }
      expect(
        await db.connection.query('merchants', where: 'id = ?',
          whereArgs: ['merchant.safeway']),
        hasLength(1),
      );
      expect(
        await db.connection.query('category_translations'),
        isNotEmpty,
      );
      expect(await db.passesIntegrityCheck(), isTrue);
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });
}
