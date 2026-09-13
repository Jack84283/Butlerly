import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_backup_engine.dart' as engine;
import 'package:butlerly/core/data/local_backup_snapshot_writer.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/local_restore_recovery.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart'
    show Sqflite, int64FromBytes;
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
/// This class adds the IMP-0010 orchestration contract: pre-restore safety
/// preservation, isolated database/evidence staging, integrity validation, and
/// activation of only a validated candidate state.
final class LocalBackupManager {
  LocalBackupManager(this.database, this.localDataManager)
    : _engine = engine.LocalBackupManager(database, localDataManager),
      _snapshotWriter = LocalBackupSnapshotWriter(localDataManager);

  final LocalDatabase database;
  final LocalDataManager localDataManager;
  final engine.LocalBackupManager _engine;
  final LocalBackupSnapshotWriter _snapshotWriter;

  static final _backupMagic = utf8.encode('BUTLERLYBACKUP2');
  static const _supportedSchemaVersion = 8;

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
    await _assertSupportedBackupSchema(file);
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
    Future<void> Function()? postActivationRefresh,
  }) => EvidenceMutationLock.runExclusive(() async {
    await recoverInterruptedLocalRestore(database, localDataManager);
    await _assertSupportedBackupSchema(file);

    // IMP-0010 requires a recovery snapshot before activation for both Merge
    // and Replace. Keep it even after success so the user has an explicit local
    // rollback artifact for the restore event.
    final safetyBackup = await _createPreRestoreSafetyBackup(mode);
    final staging = await _createStagingWorkspace();
    var liveActivated = false;
    try {
      final stagedEngine = engine.LocalBackupManager(
        staging.database,
        staging.dataManager,
      );
      final stagedResult = await stagedEngine.restore(file, mode: mode);

      // Candidate database and relationships must be valid before live state is
      // touched. The evidence engine has already verified every binary checksum.
      await _validateDatabase(staging.database.database);

      // Serialize the validated candidate as one portable state and activate it
      // through the existing transactional/crash-recovery engine. This keeps
      // structured data and evidence on the already-tested activation path while
      // ensuring the merge itself happened entirely outside live storage.
      final candidatePackage = File(
        path.join(staging.root.path, 'validated-candidate.butlerlybackup'),
      );
      final stagingManager = LocalBackupManager(
        staging.database,
        staging.dataManager,
      );
      await stagingManager.createBackup(candidatePackage);

      await _engine.restore(
        candidatePackage,
        mode: engine.LocalRestoreMode.replace,
      );
      liveActivated = true;
      await _validateDatabase(database.database);
      if (postActivationRefresh != null) {
        await postActivationRefresh();
      }
      return stagedResult;
    } catch (_) {
      if (liveActivated) {
        // A validation or runtime-refresh failure after activation must not leave
        // the user in a state that the UI reports as failed but that is actually
        // committed. Restore the pre-operation snapshot and refresh best-effort.
        try {
          await _engine.restore(
            safetyBackup,
            mode: engine.LocalRestoreMode.replace,
          );
          await _validateDatabase(database.database);
          if (postActivationRefresh != null) {
            try {
              await postActivationRefresh();
            } on Exception {
              // Preserve the original restore failure after rollback.
            }
          }
        } on Exception {
          // Preserve the original failure. Existing engine recovery markers and
          // the retained safety package provide controlled-recovery material.
        }
      }
      rethrow;
    } finally {
      await staging.dispose();
    }
  });

  Future<_RestoreStagingWorkspace> _createStagingWorkspace() async {
    final livePersistence = database.persistenceDatabase;
    final operationId = DateTime.now().microsecondsSinceEpoch;
    final root = Directory(
      path.join(
        path.dirname(livePersistence.path),
        '.butlerly-restore-stage-$operationId',
      ),
    );
    await root.create(recursive: true);
    final stagingDatabasePath = path.join(root.path, 'butlerly.db');

    // VACUUM INTO creates a consistent, standalone SQLite snapshot while the
    // live connection remains open. Quote the path as an SQLite string literal.
    final escaped = stagingDatabasePath.replaceAll("'", "''");
    await database.database.execute("VACUUM INTO '$escaped'");

    final stagingDatabase = LocalDatabase(
      logger: AppLogger(),
      factory: livePersistence.factory,
      databaseDirectory: root.path,
    );
    await stagingDatabase.initialize();

    final stagingEvidence = Directory(path.join(root.path, 'evidence'));
    final liveEvidence = await localDataManager.evidenceDirectory();
    if (await liveEvidence.exists()) {
      await _copyDirectory(liveEvidence, stagingEvidence);
    } else {
      await stagingEvidence.create(recursive: true);
    }
    final stagingDocuments = Directory(path.join(root.path, 'documents'));
    await stagingDocuments.create(recursive: true);
    final stagingData = LocalDataManager(
      stagingDatabase,
      documentsDirectory: stagingDocuments,
      localEvidenceDirectory: stagingEvidence,
    );
    return _RestoreStagingWorkspace(root, stagingDatabase, stagingData);
  }

  Future<void> _validateDatabase(Database db) async {
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    final integrityValue = integrity.isEmpty
        ? null
        : integrity.first.values.firstOrNull?.toString().toLowerCase();
    if (integrityValue != 'ok') {
      throw StateError('Restored database failed SQLite integrity validation.');
    }

    final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeys.isNotEmpty) {
      throw StateError(
        'Restored database contains broken foreign-key relationships.',
      );
    }
  }

  Future<void> _assertSupportedBackupSchema(File file) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      final magic = await raf.read(_backupMagic.length);
      if (!_listEquals(magic, _backupMagic)) return;
      final lengthBytes = await raf.read(8);
      if (lengthBytes.length != 8) return;
      final metadataLength = int64FromBytes(lengthBytes);
      if (metadataLength <= 0 || metadataLength > 128 * 1024 * 1024) return;
      final checksum = await raf.read(64);
      if (checksum.length != 64) return;
      final metadataBytes = await raf.read(metadataLength);
      if (metadataBytes.length != metadataLength) return;
      final decoded = jsonDecode(utf8.decode(metadataBytes));
      if (decoded is! Map) return;
      final metadata = decoded.cast<String, Object?>();
      final manifest = (metadata['manifest'] as Map?)?.cast<String, Object?>();
      final sourceSchema = manifest?['schemaVersion'] as int?;
      if (sourceSchema != null && sourceSchema != _supportedSchemaVersion) {
        throw FormatException(
          'Backup schema $sourceSchema is not supported by this Butlerly build.',
        );
      }
    } finally {
      await raf.close();
    }
  }

  bool _listEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Future<File> _createPreRestoreSafetyBackup(
    engine.LocalRestoreMode mode,
  ) async {
    final directory = await localDataManager.safetyBackupDirectory();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final label = mode == engine.LocalRestoreMode.merge
        ? 'Before Merge'
        : 'Before Restore';
    return createBackup(
      File(path.join(directory.path, '$label $timestamp.butlerlybackup')),
    );
  }

  Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: true, followLinks: false)) {
      final relative = path.relative(entity.path, from: source.path);
      final target = path.join(destination.path, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        final file = File(target);
        await file.parent.create(recursive: true);
        await entity.copy(file.path);
      }
    }
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

final class _RestoreStagingWorkspace {
  const _RestoreStagingWorkspace(this.root, this.database, this.dataManager);

  final Directory root;
  final LocalDatabase database;
  final LocalDataManager dataManager;

  Future<void> dispose() async {
    try {
      await database.close();
    } on Exception {
      // Continue cleaning the isolated staging directory.
    }
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } on Exception {
      // Staging cleanup is best-effort after live state has been decided.
    }
  }
}
