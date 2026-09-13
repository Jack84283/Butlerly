import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'backup restore hardening installs recovery and relationship guards',
    () async {
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
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
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name IN ('restore_commits', 'restore_context')",
      );
      expect(tables, hasLength(2));

      final membershipColumns = await database.rawQuery(
        'PRAGMA table_info(duplicate_candidate_group_transactions)',
      );
      final provenanceColumns = await database.rawQuery(
        'PRAGMA table_info(transaction_provenances)',
      );
      expect(
        membershipColumns.map((row) => row['name']),
        contains('created_at'),
      );
      expect(
        provenanceColumns.map((row) => row['name']),
        contains('created_at'),
      );

      final triggers = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'trigger'",
      );
      final names = triggers.map((row) => row['name']);
      expect(
        names,
        containsAll([
          'review_issues_tombstone',
          'duplicate_membership_tombstone',
          'duplicate_membership_preserve_newer_delete',
          'duplicate_membership_preserve_newer_update',
          'transaction_provenance_tombstone',
          'transaction_provenance_preserve_newer_delete',
          'transaction_provenance_preserve_newer_update',
          'preserve_newer_relationship_tombstone',
          'suggestions_tombstone',
          'reconciliation_candidates_tombstone',
          'duplicate_groups_tombstone',
        ]),
      );
    },
  );
}
