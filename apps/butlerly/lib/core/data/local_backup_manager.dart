import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/backup_container_format.dart';
import 'package:butlerly/core/data/backup_encryption.dart';
import 'package:butlerly/core/data/local_backup_engine.dart' as engine;
import 'package:butlerly/core/data/local_backup_snapshot_writer.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/local_restore_recovery.dart';
import 'package:butlerly/core/data/restore_recovery_state.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart'
    show Sqflite, int64FromBytes;
import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';

export 'backup_encryption.dart'
    show
        BackupPasswordOrIntegrityException,
        BackupPasswordRequiredException,
        BackupPasswordTooShortException;
export 'local_backup_engine.dart'
    show
        BackupChangeSummary,
        BackupInspection,
        LocalRestoreMode,
        LocalRestoreResult;
export 'local_restore_recovery.dart';
export 'restore_recovery_state.dart'
    show RestoreRecoveryIncident, RestoreRecoveryRequiredException;

final class LocalBackupManager {
  LocalBackupManager(
    this.database,
    this.localDataManager, {
    RestoreRecoveryState? recoveryState,
  }) : recoveryState = recoveryState ?? RestoreRecoveryState(localDataManager),
       _engine = engine.LocalBackupManager(database, localDataManager),
       _snapshotWriter = LocalBackupSnapshotWriter(localDataManager);

  final LocalDatabase database;
  final LocalDataManager localDataManager;
  final RestoreRecoveryState recoveryState;
  final engine.LocalBackupManager _engine;
  final LocalBackupSnapshotWriter _snapshotWriter;
  final BackupEncryption _encryption = const BackupEncryption();

  static final _backupMagic = BackupContainerFormat.magic;
  static const _supportedSchemaVersion = BackupContainerFormat.schemaVersion;

  Future<File> createBackup(File destination) =>
      EvidenceMutationLock.runExclusive(
        () => _createBackupUnlocked(destination),
      );

  Future<File> createPortableBackup(
    File destination, {
    required String password,
  }) async {
    final operationId = DateTime.now().microsecondsSinceEpoch;
    final privateDirectory = Directory(
      path.dirname(database.persistenceDatabase.path),
    );
    final plain = File(
      path.join(
        privateDirectory.path,
        '.portable-backup-$operationId.butlerlybackup',
      ),
    );
    final encryptedCandidate = File(
      '${destination.path}.encrypted-candidate-$operationId',
    );
    final verificationPlain = File(
      path.join(
        privateDirectory.path,
        '.portable-backup-verify-$operationId.butlerlybackup',
      ),
    );

    try {
      await EvidenceMutationLock.runExclusive(
        () => _createBackupUnlocked(plain),
      );
      await _encryption.encrypt(plain, encryptedCandidate, password: password);
      await _encryption.decrypt(
        encryptedCandidate,
        verificationPlain,
        password: password,
      );
      await _assertSupportedBackupSchema(verificationPlain);
      await _engine.inspect(verificationPlain);

      await _recoverInterruptedBackupReplacement(destination);
      await _replaceBackupFile(encryptedCandidate, destination, operationId);
      return destination;
    } finally {
      await _deleteFileBestEffort(plain);
      await _deleteFileBestEffort(verificationPlain);
      await _deleteFileBestEffort(encryptedCandidate);
      await _cleanupCandidateArtifacts(plain);
    }
  }

  Future<File> _createBackupUnlocked(File destination) async {
    final operationId = DateTime.now().microsecondsSinceEpoch;
    final candidate = File('${destination.path}.candidate-$operationId');

    try {
      final snapshotFuture = database.database.transaction((snapshot) async {
        await snapshot.rawQuery('SELECT COUNT(*) FROM sqlite_master');
        final createdAtUtc = DateTime.now().toUtc();
        await _validateDatabase(snapshot);
        await _snapshotWriter.write(
          candidate,
          source: snapshot,
          createdAtUtc: createdAtUtc,
        );
      });
      await snapshotFuture;

      await _recoverInterruptedBackupReplacement(destination);
      await _replaceBackupFile(candidate, destination, operationId);
      return destination;
    } finally {
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

    final previous = File('${destination.path}.previous-$operationId');
    await destination.rename(previous.path);
    try {
      await candidate.rename(destination.path);
    } catch (_) {
      try {
        if (await destination.exists()) await destination.delete();
        if (await previous.exists()) await previous.rename(destination.path);
      } catch (_) {}
      rethrow;
    }

    try {
      if (await previous.exists()) await previous.delete();
    } catch (_) {}
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
      for (final file in previous) {
        try {
          await file.delete();
        } catch (_) {}
      }
      return;
    }

    if (previous.length == 1) {
      await previous.single.rename(destination.path);
      return;
    }
    if (previous.length > 1) {
      throw StateError(
        'Multiple interrupted backup replacements require manual recovery.',
      );
    }
  }

  Future<void> _cleanupCandidateArtifacts(File candidate) async {
    try {
      if (await candidate.exists()) await candidate.delete();
    } catch (_) {}
    final parent = candidate.parent;
    if (!await parent.exists()) return;
    final prefix = '${path.basename(candidate.path)}.tmp-';
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! File || !path.basename(entity.path).startsWith(prefix)) {
        continue;
      }
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  Future<bool> isEncryptedBackup(File file) => _encryption.isEncrypted(file);

  Future<engine.BackupInspection> inspect(File file, {String? password}) async {
    final readable = await _openReadableBackup(file, password: password);
    try {
      await _assertSupportedBackupSchema(readable.file);
      final base = await _engine.inspect(readable.file);
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
    } finally {
      await readable.dispose();
    }
  }

  Future<void> cleanupOrphanedPrivateArtifacts() async {
    final databaseDirectory = Directory(
      path.dirname(database.persistenceDatabase.path),
    );
    if (await databaseDirectory.exists()) {
      await for (final entity in databaseDirectory.list(followLinks: false)) {
        final name = path.basename(entity.path);
        final privateStage =
            entity is Directory && name.startsWith('.butlerly-restore-stage-');
        final plaintextTemporary =
            entity is File &&
            (name.startsWith('.backup-decrypt-') ||
                name.startsWith('.portable-backup-') ||
                name.startsWith('.portable-backup-verify-'));
        if (!privateStage && !plaintextTemporary) continue;
        try {
          if (entity is Directory) {
            await entity.delete(recursive: true);
          } else if (entity is File) {
            await entity.delete();
          }
        } catch (_) {}
      }
    }

    await _pruneSafetyBackupsBestEffort(
      preservePath: recoveryState.incident?.safetyBackupPath,
    );
  }

  Future<void> recoverInterruptedRestore() =>
      EvidenceMutationLock.runExclusive(() async {
        await recoverInterruptedLocalRestore(
          database,
          localDataManager,
          recoveryState: recoveryState,
        );
        if (recoveryState.isRecoveryRequired) {
          throw const RestoreRecoveryRequiredException();
        }
      });

  Future<engine.LocalRestoreResult> restore(
    File file, {
    required engine.LocalRestoreMode mode,
    String? password,
    Future<void> Function()? postActivationRefresh,
  }) {
    if (recoveryState.isRecoveryRequired) {
      return Future<engine.LocalRestoreResult>.error(
        const RestoreRecoveryRequiredException(),
      );
    }

    return EvidenceMutationLock.runExclusive(() async {
      final readable = await _openReadableBackup(file, password: password);
      try {
        return await _restoreReadableBackup(
          readable.file,
          mode: mode,
          postActivationRefresh: postActivationRefresh,
        );
      } finally {
        await readable.dispose();
      }
    });
  }

  Future<engine.LocalRestoreResult> _restoreReadableBackup(
    File file, {
    required engine.LocalRestoreMode mode,
    Future<void> Function()? postActivationRefresh,
  }) async {
    await recoverInterruptedLocalRestore(
      database,
      localDataManager,
      recoveryState: recoveryState,
    );
    if (recoveryState.isRecoveryRequired) {
      throw const RestoreRecoveryRequiredException();
    }
    await _assertSupportedBackupSchema(file);

    final operationId = 'restore-${DateTime.now().microsecondsSinceEpoch}';
    final staging = await _createStagingWorkspace();
    File? safetyBackup;
    var liveActivated = false;
    try {
      final stagedEngine = engine.LocalBackupManager(
        staging.database,
        staging.dataManager,
      );
      await stagedEngine.restore(file, mode: mode);
      await _validateDatabase(staging.database.database);

      safetyBackup = await _createPreRestoreSafetyBackup(mode);

      final liveResult = await _restoreLivePackage(
        file,
        mode: mode,
        operationId: operationId,
        safetyBackup: safetyBackup,
      );
      liveActivated = true;
      await _validateDatabase(database.database);
      await _validateLiveEvidenceReferences();
      if (postActivationRefresh != null) {
        await postActivationRefresh();
      }

      await _clearRestoreOriginState();
      await _pruneSafetyBackupsBestEffort();
      return liveResult;
    } catch (error, stack) {
      if (liveActivated && safetyBackup != null) {
        try {
          await recoveryState.markRequired(
            operationId: operationId,
            safetyBackup: safetyBackup,
            reason: 'post-activation-validation-or-refresh-failed',
            retryCurrentState: true,
          );
        } catch (_) {}
        Error.throwWithStackTrace(
          const RestoreRecoveryRequiredException(),
          stack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      await staging.dispose();
    }
  }

  Future<engine.LocalRestoreResult> _restoreLivePackage(
    File file, {
    required engine.LocalRestoreMode mode,
    required String operationId,
    required File safetyBackup,
  }) async {
    final root = await localDataManager.evidenceDirectory();
    final journal = File('${root.path}.restore-journal.json');
    final rootExistedBeforeActivation = await root.exists();

    await _writeRestoreOriginState(
      operationId: operationId,
      rootExisted: rootExistedBeforeActivation,
      safetyBackup: safetyBackup,
    );

    try {
      return await _engine.restore(file, mode: mode);
    } catch (error, stack) {
      final journalExists = await journal.exists();
      final rootExistsAfterFailure = await root.exists();
      var rollbackProven =
          !journalExists &&
          rootExistsAfterFailure == rootExistedBeforeActivation;
      if (rollbackProven) {
        try {
          await _validateDatabase(database.database);
          await _validateLiveEvidenceReferences();
        } catch (_) {
          rollbackProven = false;
        }
      }

      if (rollbackProven) {
        await _clearRestoreOriginState();
        Error.throwWithStackTrace(error, stack);
      }

      // An uncertain engine rollback can retain a stale journal or a partially
      // activated evidence tree. Do not accept it merely because a subset of
      // current references validates; replay the exact pre-activation safety
      // snapshot instead.
      try {
        await recoveryState.markRequired(
          operationId: operationId,
          safetyBackup: safetyBackup,
          reason: 'engine-restore-recovery-pending',
          retryCurrentState: false,
        );
      } catch (_) {}
      Error.throwWithStackTrace(
        const RestoreRecoveryRequiredException(),
        stack,
      );
    }
  }

  Future<void> _writeRestoreOriginState({
    required String operationId,
    required bool rootExisted,
    required File safetyBackup,
  }) async {
    final root = await localDataManager.evidenceDirectory();
    final origin = File('${root.path}.restore-origin.json');
    final temporary = File('${origin.path}.tmp');
    final previous = File('${origin.path}.previous');
    await temporary.writeAsString(
      jsonEncode({
        'operationId': operationId,
        'rootExisted': rootExisted,
        'safetyBackupPath': safetyBackup.path,
        'activationPending': true,
      }),
      flush: true,
    );
    if (await previous.exists()) await previous.delete();
    if (await origin.exists()) await origin.rename(previous.path);
    try {
      await temporary.rename(origin.path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      rethrow;
    }
  }

  Future<void> _clearRestoreOriginState() async {
    final root = await localDataManager.evidenceDirectory();
    final origin = File('${root.path}.restore-origin.json');
    for (final file in <File>[
      origin,
      File('${origin.path}.tmp'),
      File('${origin.path}.previous'),
    ]) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> recoverControlledState({
    Future<void> Function()? postActivationRefresh,
  }) async {
    final incident = recoveryState.incident;
    if (incident == null) return;

    await EvidenceMutationLock.runExclusive(() async {
      if (incident.retryCurrentState) {
        var currentStateValid = false;
        try {
          await _validateDatabase(database.database);
          await _validateLiveEvidenceReferences();
          currentStateValid = true;
        } catch (_) {
          currentStateValid = false;
        }

        if (currentStateValid) {
          if (postActivationRefresh != null) {
            await postActivationRefresh();
          }
          await _clearRestoreOriginState();
          await recoveryState.clear();
          await _pruneSafetyBackupsBestEffort();
          return;
        }
      }

      if (incident.safetyBackupPath.isEmpty) {
        throw const RestoreRecoveryRequiredException();
      }
      final safetyBackup = File(incident.safetyBackupPath);
      if (!await safetyBackup.exists()) {
        throw const RestoreRecoveryRequiredException();
      }

      await _assertSupportedBackupSchema(safetyBackup);
      await _restoreLivePackage(
        safetyBackup,
        mode: engine.LocalRestoreMode.replace,
        operationId: 'recovery-${DateTime.now().microsecondsSinceEpoch}',
        safetyBackup: safetyBackup,
      );
      await _validateDatabase(database.database);
      await _validateLiveEvidenceReferences();
      if (postActivationRefresh != null) {
        await postActivationRefresh();
      }
      await _clearRestoreOriginState();
      await recoveryState.clear();
      await _pruneSafetyBackupsBestEffort();
    });
  }

  Future<void> resetControlledRecovery({
    Future<void> Function()? postResetRefresh,
  }) async {
    final incident = recoveryState.incident;
    if (incident == null) return;

    await localDataManager.eraseAll(preserveRecoveryMarker: true);
    try {
      if (postResetRefresh != null) await postResetRefresh();
      await _clearRestoreOriginState();
      await recoveryState.clear();
    } catch (error, stack) {
      try {
        await recoveryState.markUnknownRequired(
          operationId: incident.operationId,
          reason: 'recovery-reset-incomplete',
        );
      } catch (_) {}
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<_ReadableBackup> _openReadableBackup(
    File file, {
    String? password,
  }) async {
    if (!await _encryption.isEncrypted(file)) {
      return _ReadableBackup(file, false);
    }
    if (password == null || password.isEmpty) {
      throw const BackupPasswordRequiredException();
    }
    final directory = Directory(
      path.dirname(database.persistenceDatabase.path),
    );
    final temporary = File(
      path.join(
        directory.path,
        '.backup-decrypt-${DateTime.now().microsecondsSinceEpoch}.butlerlybackup',
      ),
    );
    try {
      await _encryption.decrypt(file, temporary, password: password);
      return _ReadableBackup(temporary, true);
    } catch (_) {
      await _deleteFileBestEffort(temporary);
      rethrow;
    }
  }

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

  Future<void> _validateDatabase(DatabaseExecutor db) async {
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

  Future<void> _validateLiveEvidenceReferences() async {
    final root = await localDataManager.evidenceDirectory();
    final rows = await database.database.query(
      'evidence_items',
      columns: ['local_file_name'],
    );
    for (final row in rows) {
      final raw = row['local_file_name'];
      if (raw is! String || raw.trim().isEmpty) continue;
      final relative = path.normalize(raw);
      if (path.isAbsolute(relative) ||
          relative == '..' ||
          relative.startsWith('../')) {
        throw StateError('Restored evidence contains an unsafe local path.');
      }
      if (!await File(path.join(root.path, relative)).exists()) {
        throw StateError('Restored database references missing evidence.');
      }
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
      if (sourceSchema != null && sourceSchema > _supportedSchemaVersion) {
        throw FormatException(
          'Backup schema $sourceSchema is newer than this Butlerly build.',
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
    return _createBackupUnlocked(
      File(path.join(directory.path, '$label $timestamp.butlerlybackup')),
    );
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
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
      'SELECT COUNT(*) FROM payment_settlements WHERE updated_at > ?',
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

  Future<void> _pruneSafetyBackupsBestEffort({String? preservePath}) async {
    try {
      await localDataManager.pruneSafetyBackups(
        keep: 2,
        preservePath: preservePath,
      );
    } catch (_) {}
  }

  Future<void> _deleteFileBestEffort(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

final class _ReadableBackup {
  const _ReadableBackup(this.file, this.temporary);

  final File file;
  final bool temporary;

  Future<void> dispose() async {
    if (!temporary) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
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
    } catch (_) {}
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {}
  }
}
