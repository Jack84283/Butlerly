import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';

const deploymentPath = 'database/migrations/deployment.sql';

Future<String> deploymentSql() => File(deploymentPath).readAsString();

Future<String> migrationSqlForVersion(
  int targetVersion, {
  bool includeBaselineHardening = true,
}) async {
  final sql = (parseDeploymentMigrations(await deploymentSql()))[targetVersion];
  if (sql == null) {
    throw StateError('Missing database migration target $targetVersion');
  }
  if (targetVersion == 8 && !includeBaselineHardening) {
    const marker = '-- BUTLERLY_BASELINE_HARDENING_BEGIN';
    final boundary = sql.indexOf(marker);
    if (boundary < 0) throw StateError('Missing migration v8 boundary');
    return sql.substring(0, boundary).trim();
  }
  return sql;
}

Future<String> baselineHardeningSql() async =>
    baselineHardeningFromDeployment(await deploymentSql());
