import 'package:butlerly_database/butlerly_database.dart';
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

  test('missing migration target fails before a database is opened', () async {
    final sql = await deploymentSql();
    final broken = sql.replaceFirst(
      '-- BUTLERLY_MIGRATION_TARGET: 15',
      '-- BUTLERLY_MIGRATION_TARGET: 16',
    );
    expect(() => parseDeploymentMigrations(broken), throwsFormatException);
  });
}
