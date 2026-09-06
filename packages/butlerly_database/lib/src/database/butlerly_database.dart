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
  });

  static const databaseVersion = 6;

  final DatabaseFactory factory;
  final String path;
  final String schemaSql;
  final List<String> seedSql;

  /// Database-owned migration SQL keyed by its target schema version.
  final Map<int, String> migrations;
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
      _database = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: databaseVersion,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: (database, _) => _executeSql(database, schemaSql),
          onUpgrade: (database, oldVersion, newVersion) async {
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
                await database.execute(statement);
              }
              if (version == 5) {
                await _backfillNormalizedDescriptions(database);
              }
            }
            if (newVersion != databaseVersion) {
              throw const RepositoryException(
                RepositoryFailureCode.migration,
                'unsupported database version',
              );
            }
          },
        ),
      );
      if (seedSql.isNotEmpty) {
        await transaction((tx) async {
          for (final sql in seedSql) {
            for (final statement in splitSqlStatements(sql)) {
              await tx.execute(statement);
            }
          }
        });
      }
    } on DatabaseException catch (error) {
      await _database?.close();
      _database = null;
      throw mapDatabaseException(error, 'open database');
    } on RepositoryException {
      await _database?.close();
      _database = null;
      rethrow;
    }
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

  Future<void> prepareForConsistentBackup() async {
    await connection.rawQuery('PRAGMA wal_checkpoint(FULL)');
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

/// Database assets use semicolon-delimited statements, line comments, and
/// single-quoted SQL strings (including doubled quote escapes).
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
    } else if (char == ';' && !quote) {
      final statement = buffer.toString().trim();
      if (statement.isNotEmpty) statements.add(statement);
      buffer.clear();
    } else {
      buffer.write(char);
    }
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
