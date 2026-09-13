import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager_v2.dart' as v2;
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/local_restore_recovery.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:sqflite_common/sqlite_api.dart';

export 'local_backup_manager_v2.dart'
    show
        BackupChangeSummary,
        BackupInspection,
        LocalRestoreMode,
        LocalRestoreResult;

final class LocalBackupManager {
  LocalBackupManager(this.database, this.localDataManager)
      : _delegate = v2.LocalBackupManager(database, localDataManager);

  final LocalDatabase database;
  final LocalDataManager localDataManager;
  final v2.LocalBackupManager _delegate;

  Future<File> createBackup(File destination) => _delegate.createBackup(destination);

  Future<v2.BackupInspection> inspect(File file) async {
    final base = await _delegate.inspect(file);
    final cutoff = base.createdAtUtc.toIso8601String();
    final additional = await _countOtherNewerData(cutoff);
    if (additional == 0) return base;
    return v2.BackupInspection(
      createdAtUtc: base.createdAtUtc,
      recordCount: base.recordCount,
      evidenceCount: base.evidenceCount,
      changes: v2.BackupChangeSummary(
        transactionsAdded: base.changes.transactionsAdded,
        transactionsChanged: base.changes.transactionsChanged,
        masterDataChanged: base.changes.masterDataChanged + additional,
        deletedEntities: base.changes.deletedEntities,
      ),
    );
  }

  Future<void> recoverInterruptedRestore() =>
      recoverInterruptedLocalRestore(database, localDataManager);

  Future<v2.LocalRestoreResult> restore(
    File file, {
    required v2.LocalRestoreMode mode,
  }) async {
    await recoverInterruptedLocalRestore(database, localDataManager);
    if (mode != v2.LocalRestoreMode.merge) {
      return _delegate.restore(file, mode: mode);
    }

    final inspection = await _delegate.inspect(file);
    await database.database.insert(
      'restore_context',
      {
        'id': 1,
        'backup_time': inspection.createdAtUtc.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      return await _delegate.restore(file, mode: mode);
    } finally {
      await database.database.delete('restore_context', where: 'id = 1');
    }
  }

  Future<int> _countOtherNewerData(String cutoff) async {
    var count = 0;
    for (final query in <String>[
      'SELECT COUNT(*) FROM evidence_items WHERE created_at > ?',
      'SELECT COUNT(*) FROM financial_statements WHERE updated_at > ?',
      'SELECT COUNT(*) FROM statement_rows WHERE updated_at > ?',
      'SELECT COUNT(*) FROM review_issues WHERE COALESCE(closed_at, created_at) > ?',
      'SELECT COUNT(*) FROM reconciliation_candidates WHERE updated_at > ?',
      'SELECT COUNT(*) FROM duplicate_candidate_groups WHERE updated_at > ?',
      'SELECT COUNT(*) FROM analysis_rule_activations WHERE updated_at > ?',
      'SELECT COUNT(*) FROM analysis_rule_configurations WHERE updated_at > ?',
      'SELECT COUNT(*) FROM user_preferences WHERE updated_at > ?',
    ]) {
      final rows = await database.database.rawQuery(query, [cutoff]);
      count += Sqflite.firstIntValue(rows) ?? 0;
    }
    return count;
  }
}
