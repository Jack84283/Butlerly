import 'dart:io';

import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart' as persistence;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'butlerly_database_test_',
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  LocalDatabase localDatabase() => LocalDatabase(
    logger: AppLogger(),
    factory: databaseFactoryFfi,
    databaseDirectory: directory.path,
  );

  test('initializes a versioned local database', () async {
    final database = localDatabase();

    await database.initialize();
    final tables = await database.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );

    expect(database.status, DatabaseStatus.ready);
    expect(
      await database.database.getVersion(),
      persistence.ButlerlyDatabase.databaseVersion,
    );
    expect(tables.map((row) => row['name']), contains('transactions'));

    await database.close();
  });

  test(
    'restores legacy dismissed Insights without touching canonical or unrelated data',
    () async {
      var database = localDatabase();
      await database.initialize();
      final db = database.database;
      final now = DateTime.utc(2026, 9, 11).toIso8601String();

      await db.insert('transactions', {
        'id': 'tx-keep',
        'unknown_time_reason': 'not supplied',
        'amount_coefficient': '42',
        'amount_scale': 0,
        'currency': 'USD',
        'direction': 'expense',
        'source_type': 'manual',
        'status': 'active',
        'created_at': now,
        'updated_at': now,
        'transaction_date': '2026-09-11',
      });
      await _insertFinding(
        db,
        id: 'dismissed-insight',
        ruleId: 'ANL-R024',
        lifecycle: 'dismissed',
        now: now,
      );
      await _insertFinding(
        db,
        id: 'active-insight',
        ruleId: 'ANL-R025',
        lifecycle: 'active',
        now: now,
      );
      await _insertFinding(
        db,
        id: 'unrelated-finding',
        ruleId: 'ANL-R999',
        lifecycle: 'dismissed',
        now: now,
      );
      await _insertResult(
        db,
        id: 'insight-result',
        ruleId: 'ANL-R024',
        surface: 'insights',
        now: now,
      );
      await _insertResult(
        db,
        id: 'overview-result',
        ruleId: 'ANL-R999',
        surface: 'overview',
        now: now,
      );
      await database.close();

      database = localDatabase();
      await database.initialize();

      expect(
        await database.database.query('analysis_findings'),
        hasLength(1),
      );
      expect(
        (await database.database.query('analysis_findings')).single['id'],
        'unrelated-finding',
      );
      expect(
        await database.database.query('analysis_rule_results'),
        hasLength(1),
      );
      expect(
        (await database.database.query('analysis_rule_results')).single['id'],
        'overview-result',
      );
      expect(
        await database.database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['tx-keep'],
        ),
        hasLength(1),
      );

      await database.close();
    },
  );

  test('keeps active Insight state when no legacy dismissal exists', () async {
    var database = localDatabase();
    await database.initialize();
    final now = DateTime.utc(2026, 9, 11).toIso8601String();

    await _insertFinding(
      database.database,
      id: 'active-insight',
      ruleId: 'ANL-R024',
      lifecycle: 'active',
      now: now,
    );
    await _insertResult(
      database.database,
      id: 'active-insight-result',
      ruleId: 'ANL-R024',
      surface: 'insights',
      now: now,
    );
    await database.close();

    database = localDatabase();
    await database.initialize();

    expect(await database.database.query('analysis_findings'), hasLength(1));
    expect(
      (await database.database.query('analysis_findings')).single['id'],
      'active-insight',
    );
    expect(
      await database.database.query('analysis_rule_results'),
      hasLength(1),
    );
    expect(
      (await database.database.query('analysis_rule_results')).single['id'],
      'active-insight-result',
    );

    await database.close();
  });
}

Future<void> _insertFinding(
  Database db, {
  required String id,
  required String ruleId,
  required String lifecycle,
  required String now,
}) => db.insert('analysis_findings', {
  'id': id,
  'rule_id': ruleId,
  'rule_version': '1.0.0',
  'definition_hash': 'test-hash',
  'period_start': '2026-09-01',
  'period_end': '2026-09-11',
  'time_zone_id': 'America/Los_Angeles',
  'payload': '{}',
  'lifecycle': lifecycle,
  'generated_at': now,
  'updated_at': now,
});

Future<void> _insertResult(
  Database db, {
  required String id,
  required String ruleId,
  required String surface,
  required String now,
}) => db.insert('analysis_rule_results', {
  'id': id,
  'rule_id': ruleId,
  'rule_version': '1.0.0',
  'definition_hash': 'test-hash',
  'result_type': 'finding',
  'surface': surface,
  'period_start': '2026-09-01',
  'period_end': '2026-09-11',
  'period_type': 'month_to_date',
  'time_zone_id': 'America/Los_Angeles',
  'dataset_mode': 'allEligible',
  'currency_basis': 'base',
  'base_currency': 'USD',
  'payload': '{}',
  'calculated_at': now,
  'source_revision': 1,
  'freshness': 'fresh',
  'created_at': now,
  'updated_at': now,
});
