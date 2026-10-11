import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/deployment_sql.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v13 to v14 adds persisted statement duplicate references', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-v14-');
    final databasePath = '${directory.path}/legacy.db';
    final current = await File('database/schema/v1.sql').readAsString();
    final legacy = current.replaceFirst(
      "      statement_rows TEXT NOT NULL DEFAULT '[]',\n",
      '',
    );
    try {
      final old = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: databasePath,
        schemaSql: legacy,
        targetVersion: 13,
      );
      await old.open();
      await old.close();

      final migration = await migrationSqlForVersion(931);
      final upgraded = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: databasePath,
        schemaSql: legacy,
        targetVersion: 14,
        migrations: {14: migration},
      );
      await upgraded.open();
      addTearDown(upgraded.close);

      expect(await upgraded.connection.getVersion(), 14);
      expect(
        await upgraded.connection.rawQuery(
          'PRAGMA table_info(duplicate_candidate_groups)',
        ),
        contains(
          predicate<Map<String, Object?>>(
            (row) => row['name'] == 'statement_rows',
          ),
        ),
      );

      final repository = SqliteDuplicateCandidateGroupRepository(upgraded);
      final now = DateTime.utc(2026, 9, 1);
      await repository.save(
        DuplicateCandidateGroup(
          id: 'duplicate:statement-row',
          transactionIds: const [],
          duplicateKey: DuplicateTransactionKey(
            transactionDate: '2026-09-01',
            amount: DecimalValue.parse('12'),
            currency: 'USD',
            direction: TransactionDirection.expense.name,
          ),
          status: DuplicateCandidateGroupStatus.unresolved,
          statementRows: const [
            DuplicateCandidateStatementRow(
              statementId: 'statement',
              rowId: 'row',
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(
        (await repository.list()).single.statementRows.single.rowId,
        'row',
      );
    } finally {
      await Directory(directory.path).delete(recursive: true);
    }
  });
}
