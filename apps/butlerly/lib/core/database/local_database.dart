import 'package:butlerly/core/database/database_factory_provider.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart' as persistence;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';

enum DatabaseStatus { notInitialized, ready, unavailable }

class LocalDatabase {
  LocalDatabase({
    required AppLogger logger,
    DatabaseFactory? factory,
    String? databaseDirectory,
  }) : _logger = logger,
       _factory = factory,
       _databaseDirectory = databaseDirectory;

  final AppLogger _logger;
  final DatabaseFactory? _factory;
  final String? _databaseDirectory;

  persistence.ButlerlyDatabase? _database;
  DatabaseStatus status = DatabaseStatus.notInitialized;

  Database get database {
    final value = _database;
    if (value == null) {
      throw StateError('The local database is not available.');
    }
    return value.connection;
  }

  persistence.ButlerlyDatabase get persistenceDatabase {
    final value = _database;
    if (value == null) {
      throw StateError('The local database is not available.');
    }
    return value;
  }

  Future<void> initialize() async {
    final factory = _factory ?? createDatabaseFactory();
    if (factory == null) {
      status = DatabaseStatus.unavailable;
      _logger.warning('SQLite is unavailable on this platform.');
      return;
    }

    final directory =
        _databaseDirectory ?? (await getApplicationSupportDirectory()).path;
    final schemaSql = await rootBundle.loadString(
      'packages/butlerly_database/database/schema/v1.sql',
    );
    final migrationV1ToV2 = await rootBundle.loadString(
      'packages/butlerly_database/database/migrations/v1_to_v2.sql',
    );
    final catalogSql = await rootBundle.loadString(
      'packages/butlerly_database/database/seed/catalog.sql',
    );
    _database = persistence.ButlerlyDatabase(
      factory: factory,
      path: path.join(directory, 'butlerly.db'),
      schemaSql: schemaSql,
      seedSql: [catalogSql],
      migrations: {2: migrationV1ToV2},
    );
    await _database!.open();
    status = DatabaseStatus.ready;
    _logger.info('Local database initialized.');
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    status = DatabaseStatus.notInitialized;
  }
}
