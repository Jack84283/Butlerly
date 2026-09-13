import 'dart:io';

import 'package:butlerly/core/data/local_backup_engine.dart' as engine;
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/local_restore_recovery.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly_database/butlerly_database.dart' show Sqflite;
import 'package:sqflite_common/sqlite_api.dart';

export 'local_backup_engine.dart'
    show
        BackupChangeSummary,
        BackupInspection,
        LocalRestoreMode,
        LocalRestoreResult;
export 'local_restore_recovery.dart';

/// Public backup/restore boundary for Butlerly.
///
/// [local_backup_engine.dart] contains the package codec and entity merge
/// mechanics; this class owns application-level snapshot and restore context.
final class LocalBackupManager {
  LocalBackupManager(this.database, this.localDataManager)
      : _engine = engine.LocalBackupManager(database, localDataManager);

  final LocalDatabase database;
  final LocalDataManager localDataManager;
  final engine.LocalBackupManager _engine;

  /// Creates a backup while a separate SQLite connection holds a write-reserved
  /// lock. Readers remain available, but no application writer can commit while
  /// the engine walks tables, so every table belongs to one logical DB state.
  ///
  /// A separate connection is deliberate: a raw BEGIN on the app's primary
  /// connection would allow unrelated queued operations to accidentally join
  /// the backup transaction.
  Future<File> createBackup(File destination) async {
    final persistence = database.persistenceDatabase;
    await database.database.execute('PRAGMA busy_timeout = 30000');
    final lock = await persistence.factory.openDatabase(
      persistence.path,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA busy_timeout = 30000');
        },
      ),
    );
    var transactionOpen = false;
    try {
      await lock.execute('BEGIN IMMEDIATE');
      transactionOpen = true;
      final result = await _engine.createBackup(destination);
      await lock.execute('COMMIT');
      transactionOpen = false;
      return result;
    } catch (_) {
      if (transactionOpen) {
        try {
          await lock.execute('ROLLBACK');
        } on Exception {
          // Preserve the original backup failure.
        }
      }
      rethrow;
    } finally {
      await lock.close();
    }
  }

  Future<engine.BackupInspection> inspect(File file) async {
    final base = await _engine.inspect(file);
    final cutoff = base.createdAtUtc.toIso8601String();
    final additional = await _countOtherNewerData(cutoff);
    if (additional == 0) return base;
    return engine.BackupInspection(
      createdAtUtc: base.createdAtUtc,
      recordCount: base.recordCount,
      evidenceCount: base.evidenceCount,
      changes: engine.BackupChangeSummary(
        transactionsAdded: base.changes.transactionsAdded,
        transactionsChanged: base.changes.transactionsChanged,
        masterDataChanged: base.changes.masterDataChanged + additional,
        deletedEntities: base.changes.deletedEntities,
      ),
    );
  }

  Future<void> recoverInterruptedRestore() =>
      recoverInterruptedLocalRestore(database, localDataManager);

  Future<engine.LocalRestoreResult> restore(
    File file, {
    required engine.LocalRestoreMode mode,
  }) async {
    await recoverInterruptedLocalRestore(database, localDataManager);
    if (mode != engine.LocalRestoreMode.merge) {
      return _engine.restore(file, mode: mode);
    }

    final inspection = await _engine.inspect(file);
    await database.database.insert(
      'restore_context',
      {
        'id': 1,
        'backup_time': inspection.createdAtUtc.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    try {
      return await _engine.restore(file, mode: mode);
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
