import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('backup restore hardening SQL installs recovery marker and child tombstones', () async {
    final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);
    final baseline = await File('database/schema/v1.sql').readAsString();
    for (final statement in splitSqlStatements(baseline)) {
      await database.execute(statement);
    }
    final hardening = await File(
      'database/migrations/v8_backup_restore_hardening.sql',
    ).readAsString();
    for (final statement in splitSqlStatements(hardening)) {
      await database.execute(statement);
    }

    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'restore_commits'",
    );
    expect(tables, hasLength(1));

    final triggers = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'trigger'",
    );
    final names = triggers.map((row) => row['name']);
    expect(
      names,
      containsAll([
        'review_issues_tombstone',
        'duplicate_membership_tombstone',
        'transaction_provenance_tombstone',
        'suggestions_tombstone',
        'reconciliation_candidates_tombstone',
        'duplicate_groups_tombstone',
      ]),
    );
  });
}
