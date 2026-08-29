import 'package:butlerly_finance_domain/butlerly_finance_domain.dart'
    show RepositoryException, RepositoryFailureCode;
import 'package:sqflite_common/sqlite_api.dart';

/// SQLite executor for database-owned schema and catalog assets.
final class ButlerlyDatabase {
  ButlerlyDatabase({
    required this.factory,
    required this.path,
    required this.schemaSql,
    this.seedSql = const [],
  });

  static const databaseVersion = 2;

  final DatabaseFactory factory;
  final String path;
  final String schemaSql;
  final List<String> seedSql;
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
            if (oldVersion < 2) {
              await database.execute(
                'ALTER TABLE statement_rows ADD COLUMN status_before_skip TEXT',
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
  if (error.isUniqueConstraintError() || error.isNotNullConstraintError()) {
    return RepositoryException(RepositoryFailureCode.constraint, operation);
  }
  if (error.isDatabaseClosedError()) {
    return RepositoryException(RepositoryFailureCode.unavailable, operation);
  }
  return RepositoryException(RepositoryFailureCode.unknown, operation);
}
