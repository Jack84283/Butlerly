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
    this.validateSchemaBeforeSeed = false,
  }) : assert(targetVersion >= 1 && targetVersion <= databaseVersion);

  static const databaseVersion = 14;

  final DatabaseFactory factory;
  final String path;
  final String schemaSql;
  final List<String> seedSql;

  /// Enable for production startup: reject incomplete schemas before seeding.
  final bool validateSchemaBeforeSeed;

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
      if (kDebugMode) {
        debugPrint('Butlerly DB: opening SQLite target v$targetVersion');
      }
      _database = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: targetVersion,
          onConfigure: (database) async {
            if (kDebugMode) {
              debugPrint('Butlerly DB: configuring SQLite connection');
            }
            await database.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (database, _) async {
            if (kDebugMode) debugPrint('Butlerly DB: creating baseline v$targetVersion');
            await _executeSql(database, schemaSql);
          },
          onUpgrade: (database, oldVersion, newVersion) async {
            if (kDebugMode) {
              debugPrint('Butlerly DB: upgrading v$oldVersion -> v$newVersion');
            }
            // A newly installed app can encounter a versioned but empty SQLite
            // file (for example, after an interrupted first launch). It has no
            // user records to migrate, so install the current baseline instead.
            // Never use this fallback for a database with any user tables.
            final tables = await database.rawQuery(
              "SELECT name FROM sqlite_master "
              "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' LIMIT 1",
            );
            if (tables.isEmpty) {
              await _executeSql(database, schemaSql);
              return;
            }
            // v13 databases created by interrupted or pre-release startup
            // may lack this specific table. Restore its definition only when
            // there are no membership records requiring the missing parent.
            if (oldVersion < 14 && newVersion >= 14) {
              await _restoreMissingDuplicateGroupsTable(database, schemaSql);
            }
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
              var statementIndex = 0;
              for (final statement in splitSqlStatements(sql)) {
                statementIndex++;
                final alteredTable = RegExp(
                  r'^ALTER\s+TABLE\s+([A-Za-z_][A-Za-z0-9_]*)\b',
                  caseSensitive: false,
                ).firstMatch(statement.trim())?.group(1);
                if (alteredTable != null) {
                  final found = await database.rawQuery(
                    "SELECT 1 FROM sqlite_master WHERE type = 'table' "
                    "AND name = ? LIMIT 1",
                    [alteredTable],
                  );
                  if (found.isEmpty) {
                    throw RepositoryException(
                      RepositoryFailureCode.migration,
                      'missing table $alteredTable during database migration',
                    );
                  }
                }
                if (await _alreadyHasAddedColumn(database, statement)) {
                  continue;
                }
                try {
                  await database.execute(statement);
                } on DatabaseException catch (error) {
                  if (kDebugMode) {
                    debugPrint('Butlerly DB: migration v$version statement '
                        '$statementIndex failed; sqliteCode=${error.getResultCode()} '
                        'object=${_schemaOperation(statement)}');
                  }
                  rethrow;
                }
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
      // A database can already advertise the target user_version while
      // missing a table after an incomplete pre-release initialization.
      // Verify this specific dependency before catalog seed triggers run.
      await _restoreMissingDuplicateGroupsTable(_database!, schemaSql);
      await _repairLegacyMerchantColumns(_database!);
      if (validateSchemaBeforeSeed) {
        await _validateBaselineTables(_database!, schemaSql);
      }
      if (kDebugMode) debugPrint('Butlerly DB: starting catalog seed');
      await seedSystemData();
      if (kDebugMode) debugPrint('Butlerly DB: catalog seed complete');
    } on DatabaseException catch (error) {
      if (kDebugMode) {
        final summary = RegExp(
          r'(?:no such table|no such column|duplicate column name):\s*'
          r'[A-Za-z_][A-Za-z0-9_]*',
          caseSensitive: false,
        ).firstMatch(error.toString())?.group(0);
        debugPrint('Butlerly DB: open failed; '
            'sqliteCode=${error.getResultCode()} '
            'schemaIssue=${summary ?? 'unclassified'}');
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

  // Pre-release databases may already carry user_version 14 while retaining
  // a merchants table from before its classification columns were introduced.
  // Add only absent nullable/defaulted columns; never discard merchant rows.
  static Future<void> _validateBaselineTables(
    Database database,
    String baselineSql,
  ) async {
    final declaredTables = <String>{};
    final tablePattern = RegExp(
      r'^CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?'
      r'([A-Za-z_][A-Za-z0-9_]*)\s*\(',
      caseSensitive: false,
    );
    for (final statement in splitSqlStatements(baselineSql)) {
      final match = tablePattern.firstMatch(statement.trim());
      if (match != null) declaredTables.add(match.group(1)!);
    }
    if (declaredTables.isEmpty) {
      throw const RepositoryException(
        RepositoryFailureCode.migration,
        'baseline schema has no table definitions',
      );
    }
    final existing = (await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )).map((row) => row['name']).whereType<String>().toSet();
    final missing = declaredTables.difference(existing).toList()..sort();
    if (missing.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('Butlerly DB: incomplete schema; '
            'missing ${missing.length} tables: ${missing.join(', ')}');
      }
      throw RepositoryException(
        RepositoryFailureCode.migration,
        'incomplete database schema: missing ${missing.join(', ')}',
      );
    }
    if (kDebugMode) {
      debugPrint('Butlerly DB: verified ${declaredTables.length} '
          'required baseline tables');
    }
  }

  static Future<void> _repairLegacyMerchantColumns(Database database) async {
    final tables = await database.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'merchants' LIMIT 1",
    );
    if (tables.isEmpty) return;
    final current = await database.rawQuery('PRAGMA table_info(merchants)');
    final existing = current.map((row) => row['name']).toSet();
    const columns = <String, String>{
      'normalized_name': "TEXT NOT NULL DEFAULT ''",
      'default_category_id': 'TEXT REFERENCES categories(id)',
      'default_subcategory_id': 'TEXT REFERENCES categories(id)',
      'is_built_in': 'INTEGER NOT NULL DEFAULT 0',
      'created_at': "TEXT NOT NULL DEFAULT ''",
      'updated_at': "TEXT NOT NULL DEFAULT ''",
    };
    for (final entry in columns.entries) {
      if (existing.contains(entry.key)) continue;
      await database.execute(
        'ALTER TABLE merchants ADD COLUMN ${entry.key} ${entry.value}',
      );
      if (kDebugMode) {
        debugPrint('Butlerly DB: restored merchants column ${entry.key}');
      }
    }
  }

  static Future<void> _restoreMissingDuplicateGroupsTable(
    Database database,
    String baselineSql,
  ) async {
    final found = await database.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'duplicate_candidate_groups' LIMIT 1",
    );
    if (found.isNotEmpty) return;

    final membership = await database.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'duplicate_candidate_group_transactions' LIMIT 1",
    );
    if (membership.isNotEmpty) {
      final linkedRecords = await database.rawQuery(
        'SELECT 1 FROM duplicate_candidate_group_transactions LIMIT 1',
      );
      if (linkedRecords.isNotEmpty) {
        throw const RepositoryException(
          RepositoryFailureCode.migration,
          'missing duplicate_candidate_groups with existing membership records',
        );
      }
    }

    final definitions = splitSqlStatements(baselineSql).where(
      (statement) => RegExp(
        r'^CREATE\s+TABLE\s+duplicate_candidate_groups\s*\(',
        caseSensitive: false,
      ).hasMatch(statement.trim()),
    );
    if (definitions.length != 1) {
      throw const RepositoryException(
        RepositoryFailureCode.migration,
        'missing duplicate_candidate_groups baseline definition',
      );
    }
    await database.execute(definitions.single);
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
      var seedIndex = 0;
      for (final sql in seedSql) {
        for (final statement in splitSqlStatements(sql)) {
          seedIndex++;
          try {
            await tx.execute(statement);
          } on DatabaseException catch (error) {
            if (kDebugMode) {
              final statementKind = RegExp(
                r'^\s*([A-Za-z_]+)',
              ).firstMatch(statement)?.group(1) ?? 'unknown';
              final table = RegExp(
                r'^\s*INSERT\s+(?:OR\s+IGNORE\s+)?INTO\s+'
                r'([A-Za-z_][A-Za-z0-9_]*)',
                caseSensitive: false,
              ).firstMatch(statement)?.group(1) ?? 'unknown';
              final reason = error.toString().split(" sql '").first;
              debugPrint('Butlerly DB: seed SQLite reason: '
                  '${reason.length > 450 ? reason.substring(0, 450) : reason}');
              debugPrint('Butlerly DB: catalog seed statement $seedIndex '
                  'failed; command=$statementKind table=$table '
                  'sqliteCode=${error.getResultCode()}');
              final schema = RegExp(
                r'(?:no such table|no such column):\s*'
                r'[A-Za-z_][A-Za-z0-9_]*',
                caseSensitive: false,
              ).firstMatch(error.toString())?.group(0);
              if (schema != null) {
                debugPrint('Butlerly DB: catalog schema issue $schema');
              }
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
      var index = 0;
      for (final statement in splitSqlStatements(sql)) {
        index++;
        try {
          await database.execute(statement);
        } on DatabaseException catch (error) {
          if (kDebugMode) {
            debugPrint('Butlerly DB: baseline statement $index failed; '
                'sqliteCode=${error.getResultCode()} '
                'object=${_schemaOperation(statement)}');
          }
          rethrow;
        }
      }
    } on DatabaseException {
      throw const RepositoryException(
        RepositoryFailureCode.migration,
        'create schema baseline',
      );
    }
  }
}

// Emits only a structural SQL identifier, never SQL values or user records.
String _schemaOperation(String statement) {
  final match = RegExp(
    r'^\s*(?:CREATE\s+(?:UNIQUE\s+)?(?:TABLE|INDEX|TRIGGER)|'
    r'ALTER\s+TABLE|DROP\s+(?:TABLE|INDEX|TRIGGER))'
    r'\s+(?:IF\s+(?:NOT\s+)?EXISTS\s+)?'
    r'([A-Za-z_][A-Za-z0-9_]*)',
    caseSensitive: false,
  ).firstMatch(statement);
  return match?.group(1) ?? 'unnamed';
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
  // SQLite reports missing schema objects as generic error code 1.
  // Treat this as an actionable migration/schema failure, not DB-UNKNOWN.
  if (raw.contains('no such table:') ||
      raw.contains('no such column:') ||
      raw.contains('duplicate column name:')) {
    return RepositoryException(
      RepositoryFailureCode.migration,
      operation,
      detail: detail,
    );
  }
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
