import 'package:butlerly_finance_domain/butlerly_finance_domain.dart'
    show RepositoryException, RepositoryFailureCode;
import 'package:sqflite_common/sqlite_api.dart';

import 'legacy_schema.dart';
import 'schema.dart';

final class ButlerlyDatabase {
  ButlerlyDatabase({
    required this.factory,
    required this.path,
    this.schemaSql,
    this.seedSql = const [],
    this.legacyCompatibility = false,
  });

  final DatabaseFactory factory;
  final String path;

  /// The framework-independent baseline loaded by the application adapter.
  /// When omitted, the legacy pre-release chain is retained for compatibility
  /// with developer databases and package-level migration tests.
  final String? schemaSql;
  final List<String> seedSql;

  /// Explicit opt-in for opening supported pre-release developer databases.
  final bool legacyCompatibility;
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
          onCreate: (database, version) => schemaSql == null
              ? legacyCompatibility
                    ? _migrate(database, 0, version)
                    : throw const RepositoryException(
                        RepositoryFailureCode.migration,
                        'fresh database requires the V1 SQL baseline',
                      )
              : _createBaseline(database, schemaSql!),
          onUpgrade: (database, from, to) {
            if (!legacyCompatibility) {
              throw const RepositoryException(
                RepositoryFailureCode.migration,
                'legacy database upgrade requires explicit compatibility mode',
              );
            }
            return _migrate(database, from, to);
          },
        ),
      );
      if (seedSql.isNotEmpty) {
        await transaction((tx) async {
          for (final sql in seedSql) {
            for (final statement in _splitSqlStatements(sql)) {
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
        for (final statement in LegacySchema.migration1) {
          await database.execute(statement);
        }
      }
      if (from < 2 && to >= 2) {
        for (final statement in LegacySchema.migration2) {
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
        for (final statement in LegacySchema.migration3) {
          await database.execute(statement);
        }
      }
      if (from < 4 && to >= 4) {
        for (final statement in LegacySchema.migration4) {
          await database.execute(statement);
        }
      }
      if (from < 5 && to >= 5) {
        for (final statement in LegacySchema.migration5) {
          await database.execute(statement);
        }
      }
      if (from < 6 && to >= 6) {
        for (final statement in LegacySchema.migration6) {
          await database.execute(statement);
        }
      }
      if (from < 7 && to >= 7) {
        for (final statement in LegacySchema.migration7) {
          await database.execute(statement);
        }
      }
      if (from < 8 && to >= 8) {
        for (final statement in LegacySchema.migration8) {
          await database.execute(statement);
        }
      }
      if (from < 9 && to >= 9) {
        for (final statement in LegacySchema.migration9) {
          await database.execute(statement);
        }
      }
      if (from < 10 && to >= 10) {
        for (final statement in LegacySchema.migration10) {
          await database.execute(statement);
        }
      }
      if (from < 11 && to >= 11) {
        for (final statement in LegacySchema.migration11) {
          await database.execute(statement);
        }
      }
      if (from < 12 && to >= 12) {
        for (final statement in LegacySchema.migration12) {
          await database.execute(statement);
        }
      }
      if (from < 13 && to >= 13) {
        for (final statement in LegacySchema.migration13) {
          await database.execute(statement);
        }
      }
      if (from < 14 && to >= 14) {
        for (final statement in LegacySchema.migration14) {
          await database.execute(statement);
        }
      }
      if (from < 15 && to >= 15) {
        for (final statement in LegacySchema.migration15) {
          await database.execute(statement);
        }
      }
      if (from < 16 && to >= 16) {
        for (final statement in LegacySchema.migration16) {
          await database.execute(statement);
        }
      }
      if (from < 17 && to >= 17) {
        for (final statement in LegacySchema.migration17) {
          await database.execute(statement);
        }
      }
      if (from < 18 && to >= 18) {
        for (final statement in LegacySchema.migration18) {
          await database.execute(statement);
        }
      }
      if (from < 19 && to >= 19) {
        for (final statement in LegacySchema.migration19) {
          await database.execute(statement);
        }
      }
      if (from < 20 && to >= 20) {
        for (final statement in LegacySchema.migration20) {
          await database.execute(statement);
        }
      }
      if (from < 21 && to >= 21) {
        for (final statement in LegacySchema.migration21) {
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

  static Future<void> _createBaseline(Database database, String sql) async {
    try {
      for (final statement in _splitSqlStatements(sql)) {
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

List<String> _splitSqlStatements(String sql) {
  final statements = <String>[];
  var buffer = StringBuffer();
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
      buffer = StringBuffer();
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
