import 'dart:io';

import 'package:butlerly/core/data/local_backup_engine.dart' as engine;
import 'package:butlerly/core/data/local_backup_snapshot_writer.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/local_restore_recovery.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
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
/// [local_backup_engine.dart] owns package validation, evidence preparation,
/// transactional merge/replace semantics, and restore crash recovery markers.
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
    await _recoverInterruptedBackupReplacement(destination);

    final operationId = DateTime.now().microsecondsSinceEpoch;
    final candidate = File('${destination.path}.candidate-$operationId');
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
      await _snapshotWriter.write(
        candidate,
        source: snapshot,
        createdAtUtc: createdAtUtc,
      );
      await snapshot.execute('COMMIT');
      transactionOpen = false;

      await _replaceBackupFile(candidate, destination, operationId);
      return destination;
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
      await _cleanupCandidateArtifacts(candidate);
    }
  }

  Future<void> _replaceBackupFile(
    File candidate,
    File destination,
    int operationId,
  ) async {
    if (!await destination.exists()) {
      await candidate.rename(destination.path);
      return;
    }

    // Never delete a known-good backup before the replacement has been
    // activated. Keep it under a deterministic sibling name so a process death
    // between the two renames is recoverable on the next backup attempt.
    final previous = File('${destination.path}.previous-$operationId');
    await destination.rename(previous.path);
    try {
      await candidate.rename(destination.path);
    } catch (_) {
      // Best-effort synchronous rollback. If this process is interrupted here,
      // _recoverInterruptedBackupReplacement preserves the previous package.
      try {
        if (await destination.exists()) await destination.delete();
        if (await previous.exists()) await previous.rename(destination.path);
      } on Exception {
        // Preserve the original replacement failure and leave the rollback file
        // for deterministic recovery on the next attempt.
      }
      rethrow;
    }

    // Cleanup after successful activation is deliberately best-effort. A stale
    // previous file is recognized and removed the next time this destination is
    // used, while the newly activated backup remains valid and available.
    try {
      if (await previous.exists()) await previous.delete();
    } on Exception {
      // Leave the rollback artifact for later cleanup.
    }
  }

  Future<void> _recoverInterruptedBackupReplacement(File destination) async {
    final parent = destination.parent;
    if (!await parent.exists()) return;
    final prefix = '${path.basename(destination.path)}.previous-';
    final previous = <File>[];
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is File && path.basename(entity.path).startsWith(prefix)) {
        previous.add(entity);
      }
    }

    if (await destination.exists()) {
      // The destination itself is authoritative after activation. Any sibling
      // rollback packages are stale cleanup residue from a successful swap.
      for (final file in previous) {
        try {
          await file.delete();
        } on Exception {
          // Cleanup must never make a valid destination unusable.
        }
      }
      return;
    }

    if (previous.length == 1) {
      await previous.single.rename(destination.path);
      return;
    }
    if (previous.length > 1) {
      // More than one rollback candidate cannot be ordered safely. Preserve all
      // packages rather than guessing which financial backup should win.
      throw StateError(
        'Multiple interrupted backup replacements require manual recovery.',
      );
    }
  }

  Future<void> _cleanupCandidateArtifacts(File candidate) async {
    try {
      if (await candidate.exists()) await candidate.delete();
    } on Exception {
      // Continue with best-effort cleanup of the writer's temporary files.
    }
    final parent = candidate.parent;
    if (!await parent.exists()) return;
    final prefix = '${path.basename(candidate.path)}.tmp-';
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! File || !path.basename(entity.path).startsWith(prefix)) {
        continue;
      }
      try {
        await entity.delete();
      } on Exception {
        // A failed backup must not mask its original error during cleanup.
      }
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
      EvidenceMutationLock.runExclusive(
        () => recoverInterruptedLocalRestore(database, localDataManager),
      );

  Future<engine.LocalRestoreResult> restore(
    File file, {
    required engine.LocalRestoreMode mode,
  }) => EvidenceMutationLock.runExclusive(() async {
    // Recovery, the optional Replace safety snapshot, evidence staging, root
    // activation, and the restore transaction all share the same evidence
    // mutation boundary. Normal capture/removal waits until restore finishes,
    // so a newly created immutable evidence file cannot be lost by a root swap.
    await recoverInterruptedLocalRestore(database, localDataManager);

    if (mode == engine.LocalRestoreMode.replace) {
      // Replace is destructive after it commits. Always preserve the current
      // local workspace in a Butlerly-managed package before mutation starts.
      await _createPreRestoreSafetyBackup();
    }

    // The engine owns one authoritative validation/staging/commit path. Nothing
    // in the live database is changed before evidence preparation succeeds.
    return _engine.restore(file, mode: mode);
  });

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
