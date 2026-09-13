import 'dart:io';

import 'package:butlerly/core/data/local_backup_engine.dart' as engine;
import 'package:butlerly/core/data/local_backup_snapshot_writer.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/local_restore_recovery.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly_database/butlerly_database.dart' show Sqflite;
import 'package:path/path.dart' as path;
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
/// [local_backup_engine.dart] owns package validation and restore mechanics.
/// [LocalBackupSnapshotWriter] owns creation from one SQLite read snapshot.
final class LocalBackupManager {
  LocalBackupManager(this.database, this.localDataManager)
    : _engine = engine.LocalBackupManager(database, localDataManager),
      _snapshotWriter = LocalBackupSnapshotWriter(localDataManager);

  final LocalDatabase database;
  final LocalDataManager localDataManager;
  final engine.LocalBackupManager _engine;
  final LocalBackupSnapshotWriter _snapshotWriter;

  /// Creates one logical database snapshot without rejecting concurrent app
  /// writes. WAL lets a dedicated reader keep its established snapshot while
  /// the primary application connection commits newer changes independently.
  Future<File> createBackup(File destination) async {
    final persistence = database.persistenceDatabase;
    await persistence.prepareForConsistentBackup();

    // WAL is persistent for the database file. It is selected before the
    // snapshot connection opens so readers and writers can overlap safely.
    await database.database.rawQuery('PRAGMA journal_mode = WAL');
    await database.database.execute('PRAGMA busy_timeout = 30000');
    final snapshot = await persistence.factory.openDatabase(
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
      await snapshot.execute('BEGIN');
      transactionOpen = true;
      // The timestamp is deliberately taken no later than the first read. If a
      // writer races this tiny boundary, Merge becomes conservatively biased
      // toward preserving the newer local row rather than overwriting it.
      final createdAtUtc = DateTime.now().toUtc();
      await snapshot.rawQuery('SELECT COUNT(*) FROM sqlite_master');
      final result = await _snapshotWriter.write(
        destination,
        source: snapshot,
        createdAtUtc: createdAtUtc,
      );
      await snapshot.execute('COMMIT');
      transactionOpen = false;
      return result;
    } catch (_) {
      if (transactionOpen) {
        try {
          await snapshot.execute('ROLLBACK');
        } on Exception {
          // Preserve the original backup failure.
        }
      }
      rethrow;
    } finally {
      await snapshot.close();
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

    if (mode == engine.LocalRestoreMode.replace) {
      // Replace is destructive after it commits. Always preserve the current
      // local workspace in a Butlerly-managed package before mutation starts.
      await _createPreRestoreSafetyBackup();
    }

    if (mode != engine.LocalRestoreMode.merge) {
      final result = await _engine.restore(file, mode: mode);
      await _purgeGeneratedWorkflowState();
      return result;
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
      // Generated rows are not authoritative and must not win a timestamp
      // comparison against a durable decision carried by the backup.
      await _purgeGeneratedWorkflowState();
      final result = await _engine.restore(file, mode: mode);
      // Older format-v2 packages may still contain generated workflow rows.
      // Purge again after restore so they are rebuilt from authoritative data.
      await _purgeGeneratedWorkflowState();
      return result;
    } finally {
      await database.database.delete('restore_context', where: 'id = 1');
    }
  }

  Future<File> _createPreRestoreSafetyBackup() async {
    final directory = await localDataManager.safetyBackupDirectory();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    return createBackup(
      File(path.join(directory.path, 'Before Restore $timestamp.butlerlybackup')),
    );
  }

  /// Generated workflow candidates are rebuilt from the restored authoritative
  /// records. Closed/resolved decisions remain because they represent explicit
  /// user intent rather than recomputable recommendations.
  Future<void> _purgeGeneratedWorkflowState() async {
    await database.database.transaction((tx) async {
      await tx.delete('review_issues', where: 'closed_at IS NULL');
      await tx.delete('suggestions', where: 'decided_at IS NULL');
      // `proposed` is the generated reconciliation state. Confirmed, rejected,
      // and undone candidates encode explicit user workflow decisions.
      await tx.delete(
        'reconciliation_candidates',
        where: "status = 'proposed'",
      );
      // Delete membership rows explicitly before unresolved groups. Historical
      // fixtures and partially migrated databases must not rely on FK cascades.
      await tx.rawDelete(
        'DELETE FROM duplicate_candidate_group_transactions '
        'WHERE group_id IN ('
        "SELECT id FROM duplicate_candidate_groups WHERE status = 'unresolved'"
        ')',
      );
      await tx.delete(
        'duplicate_candidate_groups',
        where: "status = 'unresolved'",
      );
      await tx.delete(
        'entity_tombstones',
        where:
            "entity_type IN ('review_issues', 'suggestions', "
            "'reconciliation_candidates', 'duplicate_candidate_groups', "
            "'duplicate_candidate_group_transactions')",
      );
    });
  }

  Future<int> _countOtherNewerData(String cutoff) async {
    var count = 0;
    for (final query in <String>[
      'SELECT COUNT(*) FROM evidence_items WHERE created_at > ?',
      'SELECT COUNT(*) FROM financial_statements WHERE updated_at > ?',
      'SELECT COUNT(*) FROM statement_rows WHERE updated_at > ?',
      'SELECT COUNT(*) FROM review_issues '
          'WHERE closed_at IS NOT NULL AND closed_at > ?',
      'SELECT COUNT(*) FROM suggestions '
          'WHERE decided_at IS NOT NULL AND decided_at > ?',
      "SELECT COUNT(*) FROM reconciliation_candidates "
          "WHERE status != 'proposed' AND updated_at > ?",
      "SELECT COUNT(*) FROM duplicate_candidate_groups "
          "WHERE status != 'unresolved' AND updated_at > ?",
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
