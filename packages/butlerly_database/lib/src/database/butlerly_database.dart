import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart'
    show RepositoryException, RepositoryFailureCode, normalizeMerchantName;
import 'package:sqflite_common/sqlite_api.dart';

/// SQLite executor for database-owned schema and catalog assets.
final class ButlerlyDatabase {
  ButlerlyDatabase({
    required this.factory,
    required this.path,
    required this.schemaSql,
    this.seedSql = const [],
    this.migrations = const {},
    this.targetVersion = databaseVersion,
  }) : assert(targetVersion >= 1 && targetVersion <= databaseVersion);

  static const databaseVersion = 14;

  final DatabaseFactory factory;
  final String path;
  final String schemaSql;
  final List<String> seedSql;

  /// Database-owned migration SQL keyed by its target schema version.
  final Map<int, String> migrations;

  /// Schema version this instance must open or migrate to.
  ///
  /// Application code should use the default current version. Historical
  /// migration tests and recovery tools may explicitly request an older target.
  /// Missing migration SQL below this target is an error rather than silently
  /// lowering the schema Butlerly opens.
  final int targetVersion;
  Database? _database;

  Database get connection {
    final database = _database;
    if (database == null) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'access database before opening',
      );
    }
    return database;
  }

  Future<void> open() async {
    try {
      if (kDebugMode) debugPrint('Butlerly DB: opening target v$targetVersion');
      _database = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: targetVersion,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: (database, _) async {
            if (kDebugMode) debugPrint('Butlerly DB: creating baseline');
            await _executeSql(database, schemaSql);
          },
          onUpgrade: (database, oldVersion, newVersion) async {
            if (kDebugMode) debugPrint('Butlerly DB: upgrading v$oldVersion to v$newVersion');
            for (
              var version = oldVersion + 1;
              version <= newVersion;
              version++
            ) {
              final sql = migrations[version];
              if (sql == null) {
                throw const RepositoryException(
                  RepositoryFailureCode.migration,
                  'apply database migration',
                );
              }
              for (final statement in splitSqlStatements(sql)) {
                if (await _alreadyHasAddedColumn(database, statement)) {
                  continue;
                }
                await database.execute(statement);
              }
              if (version == 5) {
                await _backfillNormalizedDescriptions(database);
              }
            }
            if (newVersion != targetVersion) {
              throw const RepositoryException(
                RepositoryFailureCode.migration,
                'unsupported database version',
              );
            }
          },
        ),
      );
      if (kDebugMode) debugPrint('Butlerly DB: seeding catalog');
      await seedSystemData();
      if (kDebugMode) debugPrint('Butlerly DB: catalog complete');
    } on DatabaseException catch (error) {
      if (kDebugMode) {
        final reason = error.toString().split(" sql '").first;
        debugPrint('Butlerly DB: sqlite failure: $reason');
      }
      await _database?.close();
      _database = null;
      throw mapDatabaseException(error, 'open database');
    } on RepositoryException {
      await _database?.close();
      _database = null;
      rethrow;
    }
  }

  static Future<bool> _alreadyHasAddedColumn(
    Database database,
    String statement,
  ) async {
    final match = RegExp(
      r'^ALTER\s+TABLE\s+([A-Za-z_][A-Za-z0-9_]*)\s+ADD\s+COLUMN\s+([A-Za-z_][A-Za-z0-9_]*)\b',
      caseSensitive: false,
    ).firstMatch(statement.trim());
    if (match == null) return false;
    final table = match.group(1)!;
    final column = match.group(2)!;
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    return columns.any((row) => row['name'] == column);
  }

  static Future<void> _backfillNormalizedDescriptions(Database database) async {
    final rows = await database.query(
      'transactions',
      columns: ['id', 'description', 'raw_counterparty'],
    );
    for (final row in rows) {
      await database.update(
        'transactions',
        {
          'normalized_description': normalizeMerchantName(
            row['description'] as String? ??
                row['raw_counterparty'] as String? ??
                '',
          ),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  /// Re-applies database-owned system catalog assets idempotently.
  ///
  /// This is used after erase/restore so master/reference data remains owned by
  /// the database package rather than duplicated in application constants.
  Future<void> seedSystemData() async {
    if (seedSql.isEmpty) return;
    await transaction((tx) async {
      for (final sql in seedSql) {
        var statementIndex = 0;
        for (final statement in splitSqlStatements(sql)) {
          statementIndex++;
          try {
            await tx.execute(statement);
          } on DatabaseException catch (error) {
            if (kDebugMode) {
              final reason = error.toString().split(" sql '").first;
              debugPrint('Butlerly DB: catalog statement $statementIndex failed: $reason');
            }
            rethrow;
          }
        }
      }
    });
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<T> transaction<T>(
    Future<T> Function(Transaction transaction) action,
  ) => connection.transaction(action);

  Future<bool> passesIntegrityCheck() async {
    final result = await connection.rawQuery('PRAGMA integrity_check');
    return result.length == 1 && result.single.values.single == 'ok';
  }

  /// Validates the live database before a logical backup begins.
  ///
  /// The backup manager owns the actual snapshot transaction. A WAL checkpoint
  /// is intentionally not performed here because checkpointing from inside an
  /// active snapshot transaction is unsafe and unnecessary for logical row
  /// serialization.
  Future<void> prepareForConsistentBackup() async {
    if (!await passesIntegrityCheck()) {
      throw const RepositoryException(
        RepositoryFailureCode.integrity,
        'prepare consistent backup',
      );
    }
  }

  static Future<void> _executeSql(Database database, String sql) async {
    try {
      for (final statement in splitSqlStatements(sql)) {
        await database.execute(statement);
      }
    } on DatabaseException {
      throw const RepositoryException(
        RepositoryFailureCode.migration,
        'create schema baseline',
      );
    }
  }
}

/// Parses the single ordered database deployment asset into upgrades keyed by
/// target SQLite user_version. Execute only steps newer than the installed DB.
Map<int, String> parseDeploymentMigrations(String deploymentSql) {
  const marker = '-- BUTLERLY_MIGRATION_TARGET:';
  final blocks = <int, StringBuffer>{};
  int? target;
  for (final line in deploymentSql.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith(marker)) {
      final parsed = int.tryParse(trimmed.substring(marker.length).trim());
      if (parsed == null ||
          parsed < 2 ||
          parsed > ButlerlyDatabase.databaseVersion ||
          blocks.containsKey(parsed) ||
          (target != null && parsed <= target)) {
        throw const FormatException('Invalid database deployment target');
      }
      target = parsed;
      blocks[parsed] = StringBuffer();
      continue;
    }
    if (target != null) blocks[target]!.writeln(line);
  }

  final result = <int, String>{};
  for (
    var version = 2;
    version <= ButlerlyDatabase.databaseVersion;
    version++
  ) {
    final sql = blocks[version]?.toString().trim();
    if (sql == null || sql.isEmpty || splitSqlStatements(sql).isEmpty) {
      throw FormatException('Missing database deployment target $version');
    }
    result[version] = sql;
  }
  return result;
}

/// The restore hardening SQL also belongs to the current fresh-install schema.
/// It is kept once in deployment.sql and reused for both fresh installs and
/// upgrades from schema v7 to v8.
String baselineHardeningFromDeployment(String deploymentSql) {
  const begin = '-- BUTLERLY_BASELINE_HARDENING_BEGIN';
  const end = '-- BUTLERLY_BASELINE_HARDENING_END';
  final start = deploymentSql.indexOf(begin);
  final finish = deploymentSql.indexOf(end);
  if (start < 0 || finish <= start + begin.length) {
    throw const FormatException('Missing baseline hardening SQL');
  }
  final sql = deploymentSql.substring(start + begin.length, finish).trim();
  if (splitSqlStatements(sql).isEmpty) {
    throw const FormatException('Empty baseline hardening SQL');
  }
  return sql;
}

/// Database assets use semicolon-delimited statements, line comments, and
/// single-quoted SQL strings (including doubled quote escapes). SQLite trigger
/// bodies may themselves contain semicolon-delimited statements, so a trigger
/// is emitted only after its terminating `END;`.
List<String> splitSqlStatements(String sql) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var quote = false;
  var comment = false;
  for (var i = 0; i < sql.length; i++) {
    final char = sql[i];
    final next = i + 1 < sql.length ? sql[i + 1] : '';
    if (comment) {
      if (char == '\n') comment = false;
      continue;
    }
    if (!quote && char == '-' && next == '-') {
      comment = true;
      i++;
      continue;
    }
    if (char == "'") {
      buffer.write(char);
      if (quote && next == "'") {
        buffer.write(next);
        i++;
      } else {
        quote = !quote;
      }
      continue;
    }
    if (char == ';' && !quote) {
      final pending = buffer.toString().trim();
      final upper = pending.toUpperCase();
      final isTrigger = upper.startsWith('CREATE TRIGGER');
      if (isTrigger && !upper.endsWith('END')) {
        buffer.write(char);
        continue;
      }
      if (pending.isNotEmpty) statements.add(pending);
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  final statement = buffer.toString().trim();
  if (statement.isNotEmpty) statements.add(statement);
  return statements;
}

RepositoryException mapDatabaseException(
  DatabaseException error,
  String operation,
) {
  final raw = error.toString().split(" sql '").first;
  final code = error.getResultCode();
  final detail =
      'sqlite${code == null ? '' : ' code=$code'}: '
      '${raw.replaceAll(RegExp(r'\s+'), ' ').trim()}';
  if (error.isUniqueConstraintError() || error.isNotNullConstraintError()) {
    return RepositoryException(
      RepositoryFailureCode.constraint,
      operation,
      detail: detail,
    );
  }
  if (error.isDatabaseClosedError()) {
    return RepositoryException(
      RepositoryFailureCode.unavailable,
      operation,
      detail: detail,
    );
  }
  return RepositoryException(
    RepositoryFailureCode.unknown,
    operation,
    detail: detail,
  );
}
