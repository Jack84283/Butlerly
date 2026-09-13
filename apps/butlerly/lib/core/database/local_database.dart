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
    final migrationV2ToV3 = await rootBundle.loadString(
      'packages/butlerly_database/database/migrations/v2_to_v3.sql',
    );
    final migrationV3ToV4 = await rootBundle.loadString(
      'packages/butlerly_database/database/migrations/v3_to_v4.sql',
    );
    final migrationV4ToV5 = await rootBundle.loadString(
      'packages/butlerly_database/database/migrations/v4_to_v5.sql',
    );
    final migrationV5ToV6 = await rootBundle.loadString(
      'packages/butlerly_database/database/migrations/v5_to_v6.sql',
    );
    final migrationV6ToV7 = await rootBundle.loadString(
      'packages/butlerly_database/database/migrations/v6_to_v7.sql',
    );
    final migrationV7ToV8 = await rootBundle.loadString(
      'packages/butlerly_database/database/migrations/v7_to_v8.sql',
    );
    final catalogSql = await rootBundle.loadString(
      'packages/butlerly_database/database/seed/catalog.sql',
    );
    _database = persistence.ButlerlyDatabase(
      factory: factory,
      path: path.join(directory, 'butlerly.db'),
      schemaSql: schemaSql,
      seedSql: [catalogSql],
      migrations: {
        2: migrationV1ToV2,
        3: migrationV2ToV3,
        4: migrationV3ToV4,
        5: migrationV4ToV5,
        6: migrationV5ToV6,
        7: migrationV6ToV7,
        8: migrationV7ToV8,
      },
    );
    await _database!.open();
    await _restoreLegacyDismissedInsights();
    status = DatabaseStatus.ready;
    _logger.info('Local database initialized.');
  }

  Future<void> _restoreLegacyDismissedInsights() async {
    final db = _database?.connection;
    if (db == null) return;

    const insightRuleIds = [
      'ANL-R014',
      'ANL-R020',
      'ANL-R021',
      'ANL-R022',
      'ANL-R023',
      'ANL-R024',
      'ANL-R025',
      'ANL-R026',
    ];
    final placeholders = List.filled(insightRuleIds.length, '?').join(', ');
    final dismissed = await db.rawQuery(
      'SELECT 1 FROM analysis_findings '
      'WHERE lifecycle = ? AND rule_id IN ($placeholders) LIMIT 1',
      ['dismissed', ...insightRuleIds],
    );
    if (dismissed.isEmpty) return;

    await db.transaction((tx) async {
      await tx.rawDelete(
        'DELETE FROM analysis_findings WHERE rule_id IN ($placeholders)',
        insightRuleIds,
      );
      await tx.delete(
        'analysis_rule_results',
        where: 'surface = ?',
        whereArgs: ['insights'],
      );
    });
    _logger.info(
      'Cleared legacy dismissed Insight state; derived Insights will rebuild.',
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    status = DatabaseStatus.notInitialized;
  }
}
