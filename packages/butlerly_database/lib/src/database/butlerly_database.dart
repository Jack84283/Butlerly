import 'package:butlerly_finance_domain/butlerly_finance_domain.dart'
    show RepositoryException, RepositoryFailureCode;
import 'package:sqflite_common/sqlite_api.dart';

import 'schema.dart';

final class ButlerlyDatabase {
  ButlerlyDatabase({required this.factory, required this.path});

  final DatabaseFactory factory;
  final String path;
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
          version: Schema.version,
          onConfigure: (database) =>
              database.execute('PRAGMA foreign_keys = ON'),
          onCreate: (database, version) => _migrate(database, 0, version),
          onUpgrade: _migrate,
        ),
      );
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'open database');
    }
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<T> transaction<T>(Future<T> Function(Transaction transaction) action) {
    return connection.transaction(action);
  }

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

  static Future<void> _migrate(Database database, int from, int to) async {
    try {
      if (from < 1 && to >= 1) {
        for (final statement in Schema.migration1) {
          await database.execute(statement);
        }
      }
      if (from < 2 && to >= 2) {
        for (final statement in Schema.migration2) {
          await database.execute(statement);
        }
        // Approved pre-release policy: preserve each legacy instant as UTC and
        // derive its business date from that UTC calendar date only.
        final legacyRows = await database.query(
          'transactions',
          columns: ['id', 'occurred_at'],
          where: 'occurred_at IS NOT NULL',
        );
        for (final row in legacyRows) {
          final utc = DateTime.parse(row['occurred_at']! as String).toUtc();
          await database.update(
            'transactions',
            {
              'occurred_at_utc': utc.toIso8601String(),
              'transaction_date': utc.toIso8601String().substring(0, 10),
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
      if (from < 3 && to >= 3) {
        for (final statement in Schema.migration3) {
          await database.execute(statement);
        }
      }
      if (from < 4 && to >= 4) {
        for (final statement in Schema.migration4) {
          await database.execute(statement);
        }
      }
    } on DatabaseException {
      throw const RepositoryException(
        RepositoryFailureCode.migration,
        'apply schema migration',
      );
    }
  }
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
