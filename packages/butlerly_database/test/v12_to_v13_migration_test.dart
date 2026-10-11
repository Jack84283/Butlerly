import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/deployment_sql.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v12 to v13 creates recurring decision storage', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-v13-');
    final databasePath = '${directory.path}/legacy.db';
    final current = await File('database/schema/v1.sql').readAsString();
    final legacy = current
        .replaceFirst(
          RegExp(
            r"CREATE TABLE recurring_pattern_decisions \(.*?\n    \);\n",
            dotAll: true,
          ),
          '',
        )
        .replaceFirst(
          RegExp(
            r"CREATE INDEX idx_recurring_pattern_decisions_key\n  ON recurring_pattern_decisions\(pattern_key\);\n",
          ),
          '',
        );
    try {
      final old = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: databasePath,
        schemaSql: legacy,
        targetVersion: 12,
      );
      await old.open();
      await old.close();

      final migration = await migrationSqlForVersion(13);
      final upgraded = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: databasePath,
        schemaSql: legacy,
        targetVersion: 13,
        migrations: {13: migration},
      );
      await upgraded.open();
      addTearDown(upgraded.close);

      expect(await upgraded.connection.getVersion(), 13);
      expect(
        await upgraded.connection.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'recurring_pattern_decisions'",
        ),
        hasLength(1),
      );

      final repository = SqliteRecurringPatternDecisionRepository(upgraded);
      final decision = RecurringPatternDecision(
        id: 'recurring-decision:legacy-pattern',
        patternKey: 'legacy-pattern',
        status: RecurringPatternDecisionStatus.confirmed,
        cadence: RecurringPatternDecisionCadence.monthly,
        intervalDays: 31,
        expectedAmount: DecimalValue.parse('12.50'),
        createdAt: DateTime.utc(2026, 8, 9, 18),
        updatedAt: DateTime.utc(2026, 8, 9, 18),
      );
      await repository.save(decision);

      final restored = await repository.findByPatternKey(decision.patternKey);
      expect(restored, isNotNull);
      expect(restored!.id, decision.id);
      expect(restored.status, decision.status);
      expect(restored.cadence, decision.cadence);
      expect(restored.intervalDays, decision.intervalDays);
      expect(restored.expectedAmount, decision.expectedAmount);
      expect(restored.createdAt, decision.createdAt);
      expect(restored.updatedAt, decision.updatedAt);
    } finally {
      await Directory(directory.path).delete(recursive: true);
    }
  });
}
