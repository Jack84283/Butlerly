import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/backup_container_format.dart';
import 'package:butlerly/core/data/backup_destination_writer.dart';
import 'package:butlerly/core/data/backup_encryption.dart';
import 'package:butlerly/core/data/backup_publication_recovery_state.dart';
import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly/core/data/local_backup_engine.dart' as engine;
import 'package:butlerly/core/data/local_backup_snapshot_writer.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/local_restore_recovery.dart';
import 'package:butlerly/core/data/restore_recovery_state.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart' show int64FromBytes;
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';

export 'backup_destination_writer.dart';
export 'backup_encryption.dart'
    show
        BackupEncryptionException,
        BackupPasswordOrIntegrityException,
        BackupPasswordRequiredException,
        BackupPasswordTooShortException;
export 'backup_publication_recovery_state.dart';
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
    BackupDestinationWriter? destinationWriter,
    BackupPublicationRecoveryStore? publicationRecoveryStore,
    BackupPublicationRecoveryState? publicationRecoveryState,
    AnalysisConsistencyGate? consistencyGate,
    OperationDiagnosticsStore? operationDiagnostics,
    Future<void> Function()? recoverStagedEvidenceDeletions,
    AppLogger? logger,
    @visibleForTesting
    Future<void> Function(Directory root)? afterStagingRootCreated,
    @visibleForTesting
    Future<void> Function(bool enabled)? foreignKeysController,
    @visibleForTesting Future<void> Function()? beforeArchiveInspection,
    @visibleForTesting Future<void> Function()? beforePostActivationValidation,
  }) : recoveryState = recoveryState ?? RestoreRecoveryState(localDataManager),
       publicationRecoveryState =
           publicationRecoveryState ?? BackupPublicationRecoveryState(),
       _afterStagingRootCreated = afterStagingRootCreated,
       _beforeArchiveInspection = beforeArchiveInspection,
       _beforePostActivationValidation = beforePostActivationValidation,
       _consistencyGate = consistencyGate,
       _operationDiagnostics = operationDiagnostics,
       _engine = engine.LocalBackupManager(
         database,
         localDataManager,
         foreignKeysController: foreignKeysController,
       ),
       _snapshotWriter = LocalBackupSnapshotWriter(localDataManager),
       _recoverStagedEvidenceDeletions = recoverStagedEvidenceDeletions,
       _logger = logger ?? AppLogger(),
       _publicationRecovery = BackupPublicationRecoveryManager(
         store: publicationRecoveryStore,
       ),
       _destinationWriter =
           destinationWriter ??
           SandboxedBackupDestinationWriter(
             recoveryStore: publicationRecoveryStore,
           );

  final LocalDatabase database;
  final LocalDataManager localDataManager;
  final RestoreRecoveryState recoveryState;
  final BackupPublicationRecoveryState publicationRecoveryState;
  final engine.LocalBackupManager _engine;
  final LocalBackupSnapshotWriter _snapshotWriter;
  final BackupPublicationRecoveryManager _publicationRecovery;
  final BackupDestinationWriter _destinationWriter;
  final Future<void> Function(Directory root)? _afterStagingRootCreated;
  final Future<void> Function()? _beforeArchiveInspection;
  final Future<void> Function()? _beforePostActivationValidation;
  final Future<void> Function()? _recoverStagedEvidenceDeletions;
  final AnalysisConsistencyGate? _consistencyGate;
  final OperationDiagnosticsStore? _operationDiagnostics;
  final AppLogger _logger;
  final BackupEncryption _encryption = const BackupEncryption();

  static final _backupMagic = BackupContainerFormat.magic;
  static const _supportedSchemaVersion = BackupContainerFormat.schemaVersion;

  Future<File> createBackup(File destination) => _runConsistently(
    () => EvidenceMutationLock.runExclusive(() async {
      final result = await _createBackupUnlocked(destination);
      await _recordArchiveDiagnostics(result, operation: 'backup');
      return result;
    }),
  );

  Future<File> createPortableBackup(
    File destination, {
    required String password,
  }) => _createPortableBackup(destination, password: password);

  /// Creates a validated encrypted archive in Butlerly-owned temporary
  /// storage. Temporary sharing files do not use external-destination
  /// publication recovery because their destination is disposable and cannot
  /// be re-authorized through the user-facing recovery picker.
  Future<File> createTemporaryBackup(
    File destination, {
    required String password,
  }) => _createPortableBackup(destination, password: password, temporary: true);

  Future<File> _createPortableBackup(
    File destination, {
    required String password,
    bool temporary = false,
  }) async {
    var stage = 'interrupted portable publication recovery';
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
      path.join(
        privateDirectory.path,
        '.portable-backup-encrypted-$operationId.butlerlybackup',
      ),
    );
    final verificationPlain = File(
      path.join(
        privateDirectory.path,
        '.portable-backup-verify-$operationId.butlerlybackup',
      ),
    );

    var preservePublicationRecovery = false;
    try {
      if (!temporary) await recoverInterruptedPortableBackupPublications();

      stage = 'SQLite snapshot and integrity validation';
      await _runConsistently(
        () => EvidenceMutationLock.runExclusive(
          () => _createBackupUnlocked(plain, onStage: (value) => stage = value),
        ),
      );

      stage = 'encryption';
      try {
        await _encryption.encrypt(
          plain,
          encryptedCandidate,
          password: password,
        );
      } on BackupPasswordTooShortException {
        rethrow;
      } on FileSystemException {
        throw const BackupStorageException();
      } catch (_) {
        throw const BackupEncryptionException();
      }

      stage = 'decryption verification';
      try {
        await _encryption.decrypt(
          encryptedCandidate,
          verificationPlain,
          password: password,
        );
      } on BackupPasswordTooShortException {
        rethrow;
      } on FileSystemException {
        throw const BackupStorageException();
      } catch (_) {
        throw const BackupEncryptionException();
      }

      stage = 'backup schema validation';
      await _assertSupportedBackupSchema(verificationPlain);

      stage = 'backup archive inspection';
      await _engine.inspect(verificationPlain);

      stage = temporary
          ? 'temporary backup file publication'
          : 'temporary file publication';
      if (temporary) {
        try {
          await destination.parent.create(recursive: true);
          await encryptedCandidate.copy(destination.path);
        } catch (_) {
          throw const BackupStorageException();
        }
      } else {
        try {
          await _destinationWriter.publish(
            source: encryptedCandidate,
            destination: destination,
            privateDirectory: privateDirectory,
            operationId: operationId.toString(),
          );
        } on BackupPublicationRecoveryRequiredException {
          rethrow;
        } on BackupDestinationWriteException {
          rethrow;
        } catch (_) {
          throw const BackupStorageException();
        }
      }
      await _recordArchiveDiagnostics(
        destination,
        operation: 'backup',
        password: password,
      );
      return destination;
    } on BackupPublicationRecoveryRequiredException catch (error, stackTrace) {
      preservePublicationRecovery = true;
      publicationRecoveryState.markRequired(error);
      _logger.severe(
        'Portable backup failed at stage: $stage',
        error,
        stackTrace,
      );
      rethrow;
    } on BackupDestinationWriteException catch (error, stackTrace) {
      preservePublicationRecovery = true;
      publicationRecoveryState.markRequired(
        BackupPublicationRecoveryRequiredException(
          'Portable backup publication requires recovery.',
          recoveries: error.recoveries,
        ),
      );
      _logger.severe(
        'Portable backup failed at stage: $stage',
        error,
        stackTrace,
      );
      rethrow;
    } on BackupStorageException catch (error, stackTrace) {
      _logger.severe(
        'Portable backup failed at stage: $stage',
        error,
        stackTrace,
      );
      rethrow;
    } on FileSystemException catch (error, stackTrace) {
      _logger.severe(
        'Portable backup failed at stage: $stage',
        error,
        stackTrace,
      );
      throw const BackupStorageException();
    } catch (error, stackTrace) {
      _logger.severe(
        'Portable backup failed at stage: $stage',
        error,
        stackTrace,
      );
      if (error is BackupEncryptionException ||
          error is BackupFailureException ||
          error is BackupPasswordTooShortException) {
        rethrow;
      }
      throw BackupFailureException(
        stage: stage,
        errorCode: _safeFailureCode(error),
      );
    } finally {
      await _deleteFileBestEffort(plain);
      await _deleteFileBestEffort(verificationPlain);
      if (!preservePublicationRecovery) {
        await _deleteFileBestEffort(encryptedCandidate);
      }
      await _cleanupCandidateArtifacts(plain);
    }
  }

  Future<File> _createBackupUnlocked(
    File destination, {
    void Function(String stage)? onStage,
  }) async {
    final operationId = DateTime.now().microsecondsSinceEpoch;
    final candidate = File('${destination.path}.candidate-$operationId');

    try {
      final snapshotFuture = database.database.transaction((snapshot) async {
        await snapshot.rawQuery('SELECT COUNT(*) FROM sqlite_master');
        final createdAtUtc = DateTime.now().toUtc();
        onStage?.call('SQLite integrity validation');
        await _validateDatabase(snapshot, requireForeignKeys: false);
        await _snapshotWriter.write(
          candidate,
          source: snapshot,
          createdAtUtc: createdAtUtc,
          onStage: onStage,
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
    var stage = 'archive decryption';
    try {
      final readable = await _openReadableBackup(file, password: password);
      try {
        stage = 'archive schema validation';
        await _assertSupportedBackupSchema(readable.file);
        stage = 'archive inspection';
        await _beforeArchiveInspection?.call();
        return await _engine.inspect(readable.file);
      } finally {
        await readable.dispose();
      }
    } catch (error, stackTrace) {
      _logger.severe(
        'Backup inspection failed at stage: $stage',
        error,
        stackTrace,
      );
      if (error is DatabaseException) {
        Error.throwWithStackTrace(
          BackupFailureException(stage: stage, errorCode: 'database'),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<void> recoverInterruptedPortableBackupPublications({
    String? authorizedDestinationPath,
  }) async {
    try {
      await _publicationRecovery.recover(
        Directory(path.dirname(database.persistenceDatabase.path)),
        authorizedDestinationPath: authorizedDestinationPath,
      );
      publicationRecoveryState.clear();
    } on BackupPublicationRecoveryRequiredException catch (error) {
      publicationRecoveryState.markRequired(error);
      rethrow;
    }
  }

  /// Lets the user continue using the live workspace without claiming that an
  /// external backup publication succeeded. Recovery artifacts and their
  /// destination-unknown marker remain on disk so the operation can be retried
  /// later, including after the next launch.
  void dismissPortableBackupPublicationRecovery() {
    publicationRecoveryState.clear();
  }

  Future<void> cleanupOrphanedPrivateArtifacts() async {
    final databaseDirectory = Directory(
      path.dirname(database.persistenceDatabase.path),
    );
    var preserveAllPortableArtifacts = false;
    final protectedPortableArtifacts = <String>{};
    if (await databaseDirectory.exists()) {
      try {
        protectedPortableArtifacts.addAll(
          await _publicationRecovery.activeArtifactNames(databaseDirectory),
        );
        preserveAllPortableArtifacts = protectedPortableArtifacts.remove('*');
      } on Exception {
        preserveAllPortableArtifacts = true;
      }
      await for (final entity in databaseDirectory.list(followLinks: false)) {
        final name = path.basename(entity.path);
        final privateStage =
            entity is Directory && name.startsWith('.butlerly-restore-stage-');
        final privateTemporary =
            entity is File &&
            (name.startsWith('.backup-decrypt-') ||
                name.startsWith('.portable-backup-') ||
                name.startsWith('.portable-backup-verify-'));
        if (!privateStage && !privateTemporary) continue;
        if (privateTemporary &&
            (preserveAllPortableArtifacts ||
                protectedPortableArtifacts.contains(name))) {
          continue;
        }
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
  }) => _runConsistently(() async {
    var stage = 'restore recovery initialization';
    try {
      if (recoveryState.isRecoveryRequired) {
        throw const RestoreRecoveryRequiredException();
      }

      return await EvidenceMutationLock.runExclusive(() async {
        stage = 'archive decryption';
        final readable = await _openReadableBackup(file, password: password);
        try {
          return await _restoreReadableBackup(
            readable.file,
            mode: mode,
            postActivationRefresh: postActivationRefresh,
            onStage: (value) => stage = value,
          );
        } finally {
          await readable.dispose();
        }
      });
    } catch (error, stackTrace) {
      _logger.severe('Restore failed at stage: $stage', error, stackTrace);
      if (error is BackupPasswordOrIntegrityException ||
          error is BackupPasswordRequiredException ||
          error is RestoreFailureException ||
          error is RestoreRecoveryRequiredException) {
        rethrow;
      }
      throw RestoreFailureException(
        stage: stage,
        errorCode: _safeFailureCode(error),
      );
    }
  });

  Future<engine.LocalRestoreResult> _restoreReadableBackup(
    File file, {
    required engine.LocalRestoreMode mode,
    Future<void> Function()? postActivationRefresh,
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('restore recovery initialization');
    await recoverInterruptedLocalRestore(
      database,
      localDataManager,
      recoveryState: recoveryState,
    );
    if (recoveryState.isRecoveryRequired) {
      throw const RestoreRecoveryRequiredException();
    }
    onStage?.call('archive schema validation');
    await _assertSupportedBackupSchema(file);

    final operationId = 'restore-${DateTime.now().microsecondsSinceEpoch}';
    onStage?.call('staging workspace creation');
    final staging = await _createStagingWorkspace();
    File? safetyBackup;
    var liveActivated = false;
    try {
      final stagedEngine = engine.LocalBackupManager(
        staging.database,
        staging.dataManager,
      );
      onStage?.call('staged database restore');
      final stagedResult = await stagedEngine.restore(file, mode: mode);
      onStage?.call('staged database validation');
      final allowLegacyUnresolvedReferences =
          stagedResult.usesLegacyUnresolvedReferenceWarnings;
      await _validateDatabase(
        staging.database.database,
        requireForeignKeys: !_allowsMissingReferencedRecords(stagedResult),
        allowedUnresolvedReferenceKeys:
            stagedResult.preservesUnresolvedReferences &&
                !allowLegacyUnresolvedReferences
            ? stagedResult.unresolvedReferenceKeys
            : null,
      );

      onStage?.call('pre-restore safety backup');
      safetyBackup = await _createPreRestoreSafetyBackup(
        mode,
        onStage: (backupStage) =>
            onStage?.call('pre-restore safety backup: $backupStage'),
      );

      onStage?.call('live activation');
      final liveResult = await _restoreLivePackage(
        file,
        mode: mode,
        operationId: operationId,
        safetyBackup: safetyBackup,
      );
      liveActivated = true;
      onStage?.call('post-activation validation and refresh');
      await _beforePostActivationValidation?.call();
      await _validateDatabase(
        database.database,
        requireForeignKeys: !_allowsMissingReferencedRecords(liveResult),
        allowedUnresolvedReferenceKeys:
            stagedResult.preservesUnresolvedReferences &&
                !allowLegacyUnresolvedReferences
            ? stagedResult.unresolvedReferenceKeys
            : null,
      );
      await _validateLiveEvidenceReferences();
      var analysisRebuildFailed = false;
      if (postActivationRefresh != null) {
        try {
          await postActivationRefresh();
        } catch (error, stackTrace) {
          // The primary restore is already committed and validated. A
          // recalculation failure must be reported as a warning, not turn a
          // safe source-data restore into a rollback incident.
          analysisRebuildFailed = true;
          _logger.warning(
            'Derived analysis rebuild failed after restore',
            error.runtimeType.toString(),
            stackTrace,
          );
        }
      }

      await _clearRestoreOriginState();
      await _pruneSafetyBackupsBestEffort();
      final result = LocalRestoreResult(
        mode: liveResult.mode,
        restoredRows: liveResult.restoredRows,
        keptNewerLocalRows: liveResult.keptNewerLocalRows,
        restoredEvidence: liveResult.restoredEvidence,
        preservesUnresolvedReferences: liveResult.preservesUnresolvedReferences,
        unresolvedReferenceKeys: liveResult.unresolvedReferenceKeys,
        usesLegacyUnresolvedReferenceWarnings:
            liveResult.usesLegacyUnresolvedReferenceWarnings,
        warnings: liveResult.warnings,
        analysisRebuildFailed: analysisRebuildFailed,
      );
      await _recordRestoreDiagnostics(result);
      return result;
    } catch (error, stack) {
      if (liveActivated && safetyBackup != null) {
        final failureStage = error is RestoreFailureException
            ? error.stage
            : 'post-activation validation and refresh';
        final failureCode = _boundedFailureCode(
          error is RestoreFailureException
              ? error.errorCode
              : error is RestoreRecoveryRequiredException
              ? error.errorCode ?? _safeFailureCode(error)
              : _safeFailureCode(error),
        );
        try {
          await recoveryState.markRequired(
            operationId: operationId,
            safetyBackup: safetyBackup,
            reason: 'post-activation-validation-or-refresh-failed',
            retryCurrentState: true,
            diagnostic: _restoreRecoveryDiagnostic(
              stage: failureStage,
              errorCode: failureCode,
            ),
          );
        } catch (_) {}
        Error.throwWithStackTrace(
          RestoreRecoveryRequiredException(
            stage: _boundedFailureStage(failureStage),
            errorCode: failureCode,
          ),
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
          diagnostic: _restoreRecoveryDiagnostic(
            stage: 'live activation',
            errorCode: _safeFailureCode(error),
          ),
        );
      } catch (_) {}
      Error.throwWithStackTrace(
        RestoreRecoveryRequiredException(
          stage: 'live activation',
          errorCode: _safeFailureCode(error),
        ),
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
    await rejectSymlinkedPath(origin.path);
    await rejectSymlinkedPath(temporary.path);
    await rejectSymlinkedPath(previous.path);
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

  Future<void> _recordArchiveDiagnostics(
    File archive, {
    required String operation,
    String? password,
  }) async {
    final store = _operationDiagnostics;
    if (store == null) return;
    try {
      final readable = await _openReadableBackup(archive, password: password);
      try {
        final inspection = await _engine.inspect(readable.file);
        await _recordOperationFindings(operation, [
          for (final warning in inspection.warnings)
            _findingForWarning(operation, warning, DateTime.now().toUtc()),
        ]);
      } finally {
        await readable.dispose();
      }
    } on Object catch (error, stackTrace) {
      // Diagnostic persistence is advisory. Never turn a successfully
      // published archive into a failed backup because its history row could
      // not be written.
      _logger.warning(
        'Operation diagnostic recording failed',
        error.runtimeType.toString(),
        stackTrace,
      );
    }
  }

  Future<void> _recordRestoreDiagnostics(LocalRestoreResult result) async {
    final findings = [
      for (final warning in result.warnings)
        _findingForWarning('restore', warning, DateTime.now().toUtc()),
      if (result.analysisRebuildFailed)
        DataIntegrityFinding(
          id: 'restore:analysis_rebuild_failed',
          code: 'analysis_rebuild_failed',
          category: DataIntegrityFindingCategory.analysisInconsistency,
          severity: DataIntegrityFindingSeverity.warning,
          description: 'Derived analysis could not be rebuilt after restore.',
          affectedRecords: const [],
          context: const {},
          recommendedAction:
              'Review Data Integrity Reports and retry analysis when available.',
          detectedAtUtc: DateTime.now().toUtc(),
        ),
    ];
    await _recordOperationFindings('restore', findings);
  }

  Future<void> _recordOperationFindings(
    String operation,
    List<DataIntegrityFinding> findings,
  ) async {
    final store = _operationDiagnostics;
    if (store == null || findings.isEmpty) return;
    try {
      await store.record(operation: operation, findings: findings);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Operation diagnostic recording failed',
        error.runtimeType.toString(),
        stackTrace,
      );
    }
  }

  DataIntegrityFinding _findingForWarning(
    String operation,
    BackupWarning warning,
    DateTime detectedAtUtc,
  ) {
    final records = [...warning.affectedRecords]
      ..sort((left, right) {
        final typeOrder = left.type.compareTo(right.type);
        return typeOrder == 0 ? left.id.compareTo(right.id) : typeOrder;
      });
    final recordKey = records.map((record) => '${record.type}:${record.id}');
    final category = switch (warning.code) {
      'missing_receipt' => DataIntegrityFindingCategory.missingReceipt,
      'missing_evidence' => DataIntegrityFindingCategory.missingAttachment,
      'invalid_custom_analysis_rule' =>
        DataIntegrityFindingCategory.analysisInconsistency,
      'invalid_custom_configuration' =>
        DataIntegrityFindingCategory.invalidCustomConfiguration,
      'missing_referenced_record' =>
        DataIntegrityFindingCategory.missingReferencedRecord,
      'relationship_inconsistency' =>
        DataIntegrityFindingCategory.relationshipInconsistency,
      _ => DataIntegrityFindingCategory.analysisInconsistency,
    };
    final severity = switch (warning.code) {
      'missing_receipt' => DataIntegrityFindingSeverity.warning,
      'missing_evidence' => DataIntegrityFindingSeverity.warning,
      _ => DataIntegrityFindingSeverity.error,
    };
    final description = switch (warning.code) {
      'missing_receipt' =>
        'Receipt content referenced by this operation was unavailable.',
      'missing_evidence' =>
        'Attachment or evidence content referenced by this operation was unavailable.',
      'invalid_custom_analysis_rule' =>
        'A user analysis rule definition is incomplete or invalid.',
      'invalid_custom_configuration' =>
        'A user analysis rule configuration is not valid JSON.',
      'missing_referenced_record' =>
        'A record referenced by this operation was unavailable.',
      'relationship_inconsistency' =>
        'A local record contains an inconsistent relationship.',
      _ => 'The operation encountered local data that needs review.',
    };
    final recommendedAction = switch (warning.code) {
      'missing_receipt' =>
        'Attach the original receipt again from the affected record.',
      'missing_evidence' =>
        'Attach the original file again from the affected record.',
      'invalid_custom_analysis_rule' =>
        'Review the rule configuration or reinstall the rule from its original source.',
      'invalid_custom_configuration' =>
        'Review the rule configuration and correct it before running analysis.',
      'missing_referenced_record' =>
        'Review the affected records and restore the missing related data from a trusted source.',
      'relationship_inconsistency' =>
        'Review the affected records and correct the relationship manually.',
      _ =>
        'Review the affected local data and choose a safe corrective action.',
    };
    return DataIntegrityFinding(
      id: '$operation:${warning.code}:${recordKey.join('|')}',
      code: warning.code,
      category: category,
      severity: severity,
      description: description,
      affectedRecords: List.unmodifiable(records),
      context: {'operation': operation, 'count': '${warning.count}'},
      recommendedAction: recommendedAction,
      detectedAtUtc: detectedAtUtc,
    );
  }

  Future<void> recoverControlledState({
    Future<void> Function()? postActivationRefresh,
  }) => _runConsistently(() async {
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
          await _recoverStagedEvidenceBeforeClearing();
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
      final restored = await _restoreLivePackage(
        safetyBackup,
        mode: engine.LocalRestoreMode.replace,
        operationId: 'recovery-${DateTime.now().microsecondsSinceEpoch}',
        safetyBackup: safetyBackup,
      );
      await _validateDatabase(
        database.database,
        requireForeignKeys: !_allowsMissingReferencedRecords(restored),
        allowedUnresolvedReferenceKeys:
            restored.preservesUnresolvedReferences &&
                !restored.usesLegacyUnresolvedReferenceWarnings
            ? restored.unresolvedReferenceKeys
            : null,
      );
      await _validateLiveEvidenceReferences();
      await _recoverStagedEvidenceBeforeClearing();
      if (postActivationRefresh != null) {
        await postActivationRefresh();
      }
      await _clearRestoreOriginState();
      await recoveryState.clear();
      await _pruneSafetyBackupsBestEffort();
    });
  });

  Future<void> _recoverStagedEvidenceBeforeClearing() async {
    final recover = _recoverStagedEvidenceDeletions;
    if (recover != null) await recover();
  }

  Future<void> resetControlledRecovery({
    Future<void> Function()? postResetRefresh,
  }) => _runConsistently(() async {
    final incident = recoveryState.incident;
    if (incident == null) return;

    await localDataManager.eraseAll(preserveRecoveryMarker: true);
    publicationRecoveryState.clear();
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
  });

  Future<T> _runConsistently<T>(Future<T> Function() operation) {
    final gate = _consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
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
    await rejectSymlinkedPath(root.path);
    LocalDatabase? stagingDatabase;
    try {
      await root.create(recursive: true);
      if (_afterStagingRootCreated != null) {
        await _afterStagingRootCreated(root);
      }
      final stagingDatabasePath = path.join(root.path, 'butlerly.db');

      final escaped = stagingDatabasePath.replaceAll("'", "''");
      await database.database.execute("VACUUM INTO '$escaped'");

      stagingDatabase = LocalDatabase(
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
    } catch (_) {
      try {
        await stagingDatabase?.close();
      } catch (_) {}
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _validateDatabase(
    DatabaseExecutor db, {
    bool requireForeignKeys = true,
    List<String>? allowedUnresolvedReferenceKeys,
  }) async {
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    final integrityValue = integrity.isEmpty
        ? null
        : integrity.first.values.firstOrNull?.toString().toLowerCase();
    if (integrityValue != 'ok') {
      throw StateError('Restored database failed SQLite integrity validation.');
    }

    if (!requireForeignKeys && allowedUnresolvedReferenceKeys == null) return;
    final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeys.isNotEmpty &&
        (requireForeignKeys ||
            allowedUnresolvedReferenceKeys == null ||
            foreignKeys.any(
              (violation) => !_isAllowedUnresolvedReference(
                violation,
                allowedUnresolvedReferenceKeys,
              ),
            ))) {
      throw StateError(
        'Restored database contains broken foreign-key relationships.',
      );
    }
  }

  bool _isAllowedUnresolvedReference(
    Map<String, Object?> violation,
    List<String> allowedKeys,
  ) {
    // Current archives may preserve any unresolved source relationship. Only
    // violations observed in the isolated archive restore are allowed through
    // live validation; a new or altered violation remains fatal.
    final key =
        '${violation['table']}|${violation['rowid']}|'
        '${violation['parent']}|${violation['fkid']}';
    return allowedKeys.contains(key);
  }

  bool _allowsMissingReferencedRecords(LocalRestoreResult result) =>
      result.preservesUnresolvedReferences ||
      result.usesLegacyUnresolvedReferenceWarnings;

  Future<void> _validateLiveEvidenceReferences() async {
    final root = await localDataManager.evidenceDirectory();
    await rejectEvidenceRoot(root);
    final rows = await database.database.query(
      'evidence_items',
      columns: ['local_file_name'],
    );
    for (final row in rows) {
      final raw = row['local_file_name'];
      if (raw == null) continue;
      if (raw is! String) {
        throw StateError('Restored evidence contains a non-string path.');
      }
      if (raw.trim().isEmpty) continue;
      try {
        await validateEvidenceReferencePath(
          root,
          raw,
          message: 'Restored evidence contains an unsafe local path.',
        );
      } on FormatException catch (error) {
        throw StateError(error.message);
      }
      // Missing optional evidence is preserved as metadata and surfaced by
      // Data Integrity Reports. Restore only needs to prove that any path
      // that is present is safely contained by the app-owned evidence root.
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
      if (sourceSchema != null &&
          (sourceSchema < 8 || sourceSchema > _supportedSchemaVersion)) {
        throw FormatException(
          'Backup schema $sourceSchema is not supported by this Butlerly build.',
        );
      }
      if (sourceSchema != null) {
        final tables = (metadata['tables'] as Map?)?.cast<String, Object?>();
        if (tables == null) {
          throw const FormatException('Backup metadata is missing its tables.');
        }
        final missing = engine.LocalBackupManager.requiredTablesForSchema(
          sourceSchema,
        ).where((table) => !tables.containsKey(table)).toList()..sort();
        if (missing.isNotEmpty) {
          throw FormatException(
            'Backup schema $sourceSchema is missing required tables: '
            '${missing.join(', ')}.',
          );
        }
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
    engine.LocalRestoreMode mode, {
    void Function(String stage)? onStage,
  }) async {
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
      onStage: onStage,
    );
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await rejectEvidenceRoot(source);
    await destination.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      await rejectEvidenceLink(entity);
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

String _safeFailureCode(Object error) {
  if (error is BackupFailureException) {
    return _boundedFailureCode(error.errorCode);
  }
  if (error is RestoreFailureException) {
    return _boundedFailureCode(error.errorCode);
  }
  if (error is RestoreRecoveryRequiredException) {
    return _boundedFailureCode(error.errorCode ?? 'restore_recovery_required');
  }
  if (error is FileSystemException) return 'filesystem';
  if (error is DatabaseException) return 'database';
  if (error is FormatException) return 'format';
  if (error is StateError) return 'state';
  if (error is ArgumentError) return 'invalid_argument';
  return 'unknown';
}

String _boundedFailureCode(String code) {
  return RestoreRecoveryDiagnostic.errorCodes.contains(code) ? code : 'unknown';
}

String _boundedFailureStage(String stage) {
  final value = stage.toLowerCase();
  if (value.contains('database validation') ||
      value.contains('post-activation validation')) {
    return 'post-activation validation and refresh';
  }
  if (value.contains('restore activation') || value == 'live activation') {
    return 'live activation';
  }
  return 'restore validation';
}

RestoreRecoveryDiagnostic _restoreRecoveryDiagnostic({
  required String stage,
  required String errorCode,
}) => RestoreRecoveryDiagnostic(
  stageCode: switch (_boundedFailureStage(stage)) {
    'live activation' => 'restore_activation',
    _ => 'restore_validation',
  },
  errorCode: _boundedFailureCode(errorCode),
);

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
