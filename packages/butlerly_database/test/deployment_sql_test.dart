import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/deployment_sql.dart';

void main() {
  test('deployment includes all schema versions', () async {
    final upgrades = parseDeploymentMigrations(await deploymentSql());
    expect(
      upgrades.keys.toList(),
      List<int>.generate(ButlerlyDatabase.databaseVersion - 1, (i) => i + 2),
    );
    for (final sql in upgrades.values) {
      expect(splitSqlStatements(sql), isNotEmpty);
    }
  });

  test('hardening is shared by fresh create and v8 upgrade', () async {
    final sql = await deploymentSql();
    final hardening = baselineHardeningFromDeployment(sql);
    final upgrade = parseDeploymentMigrations(sql)[8]!;
    expect(hardening, contains('restore_context'));
    expect(upgrade, contains(hardening));
    expect(splitSqlStatements(hardening), isNotEmpty);
  });

  test('v20 indexes upgrade an existing SQLite workspace without data loss', (
    ) async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp(
      'butlerly-v20-upgrade-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final path = '${directory.path}/workspace.db';
    final baseline = await File('database/schema/v1.sql').readAsString();
    const trimmedIndex = '''CREATE INDEX IF NOT EXISTS idx_settlement_source_trimmed_date
  ON transactions(payment_source_id, TRIM(transaction_date));''';
    const instantIndex = '''CREATE INDEX IF NOT EXISTS idx_settlement_source_occurred_at
  ON transactions(payment_source_id, occurred_at);''';
    expect(baseline, contains(trimmedIndex));
    expect(baseline, contains(instantIndex));
    final legacy = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: path,
      schemaSql: baseline
          .replaceFirst(trimmedIndex, '')
          .replaceFirst(instantIndex, ''),
      targetVersion: 19,
    );
    await legacy.open(seedSystemDataOnOpen: false);
    await legacy.connection.insert('payment_sources', {
      'id': 'upgrade-card',
      'name': 'Preserved card',
      'type': 'card',
      'status': 'active',
    });
    await legacy.connection.insert('transactions', {
      'id': 'upgrade-transaction',
      'occurred_at': '2026-09-15T12:00:00.000Z',
      'amount_coefficient': '125',
      'amount_scale': 2,
      'currency': 'USD',
      'direction': 'expense',
      'source_type': 'import',
      'status': 'active',
      'payment_source_id': 'upgrade-card',
      'transaction_date': ' 2026-09-15 ',
      'created_at': '2026-09-15T12:00:00.000Z',
      'updated_at': '2026-09-15T12:00:00.000Z',
    });
    await legacy.close();

    final deployment = await deploymentSql();
    final latest = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: path,
      schemaSql: baseline,
      migrations: {20: parseDeploymentMigrations(deployment)[20]!},
    );
    try {
      await latest.open(seedSystemDataOnOpen: false);
      final indexes = await latest.connection.rawQuery(
        'PRAGMA index_list(transactions)',
      );
      final names = indexes.map((row) => row['name']).toSet();
      expect(names, contains('idx_settlement_source_trimmed_date'));
      expect(names, contains('idx_settlement_source_occurred_at'));
      final preserved = await latest.connection.query(
        'transactions',
        columns: ['id', 'amount_coefficient', 'transaction_date'],
      );
      expect(preserved, hasLength(1));
      expect(preserved.single['id'], 'upgrade-transaction');
      expect(preserved.single['amount_coefficient'], '125');
      expect(preserved.single['transaction_date'], ' 2026-09-15 ');
    } finally {
      await latest.close();
    }
  });

  test('missing migration target fails before a database is opened', () async {
    final sql = await deploymentSql();
    final broken = sql.replaceFirst(
      '-- BUTLERLY_MIGRATION_TARGET: 15',
      '-- BUTLERLY_MIGRATION_TARGET: 16',
    );
    expect(() => parseDeploymentMigrations(broken), throwsFormatException);
  });
}
