import 'dart:io';

import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/raw_backup_archive.dart';
import 'package:butlerly/core/data/raw_backup_service.dart';
import 'package:butlerly/core/data/raw_merge_service.dart';
import 'package:butlerly/core/data/raw_restore_service.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Local adapter for application-owned privacy and recovery operations.
final class LocalWorkspaceDataGateway implements LocalDataGateway {
  LocalWorkspaceDataGateway(
    this.backups,
    this.data, {
    this.restoreDiagnosticStage,
  }) {
    _rawBackups = RawBackupService(data.database, data);
    _rawRestores = RawRestoreService(data.database, _rawBackups);
    _rawMerges = RawMergeService(data.database, _rawBackups, _rawRestores);
  }

  final LocalBackupManager backups;
  final LocalDataManager data;

  /// Optional fault-injection / diagnostic hook; never set by the UI.
  final Future<void> Function(String stage)? restoreDiagnosticStage;
  late final RawBackupService _rawBackups;
  late final RawRestoreService _rawRestores;
  late final RawMergeService _rawMerges;

  @override
  bool get hasRecoverySafetyCopy =>
      backups.recoveryState.incident?.safetyBackupPath.isNotEmpty == true;

  /// Adapt publication safety errors into the application-owned error contract,
  /// without exposing internal recovery paths to the UI.
  Future<BackupCreationResult> _createRawBackup(
    File file,
    String password,
  ) async {
    try {
      final inspection = await _rawBackups.createBackup(
        file,
        password: password,
      );
      return BackupCreationResult(
        attachmentCount: inspection.attachmentCount,
        missingAttachmentCount: inspection.missingAttachmentCount,
      );
    } on BackupPublicationRecoveryRequiredException catch (error, stack) {
      Error.throwWithStackTrace(
        BackupCreationException(
          stage: BackupCreationStage.publication,
          cause: error,
          recoveryRequired: true,
        ),
        stack,
      );
    } on BackupDestinationWriteException catch (error, stack) {
      Error.throwWithStackTrace(
        BackupCreationException(
          stage: BackupCreationStage.publication,
          cause: error,
          recoveryRequired: true,
        ),
        stack,
      );
    }
  }

  @override
  Future<BackupCreationResult> createPortableBackup(
    String destination, {
    required String password,
  }) => _createRawBackup(File(destination), password);

  @override
  Future<void> recoverPortableBackupPublication(String destination) =>
      backups.recoverInterruptedPortableBackupPublications(
        authorizedDestinationPath: destination,
      );

  static final _shareDirectoryName = RegExp(
    r'^\.butlerly-backup-share-[0-9]{13,20}

  @override
  Future<bool> isEncryptedBackup(String filePath) =>
      backups.isEncryptedBackup(File(filePath));

  @override
  Future<BackupInspection> inspect(String filePath, {String? password}) async {
    if (password == null || password.isEmpty) {
      throw const BackupPasswordRequiredException();
    }
    final result = await _rawBackups.inspect(
      File(filePath),
      password: password,
    );
    return BackupInspection(
      createdAtUtc: result.createdAtUtc,
      recordCount: result.recordCount,
      evidenceCount: result.attachmentCount,
      missingEvidenceCount: result.missingAttachmentCount,
      // Raw snapshot inspection never interprets newer local financial rows.
      changes: const BackupChangeSummary(
        transactionsAdded: 0,
        transactionsChanged: 0,
        masterDataChanged: 0,
        deletedEntities: 0,
      ),
    );
  }

  @override
  Future<LocalRestoreResult> restore(
    String filePath, {
    required LocalRestoreMode mode,
    String? password,
    required Future<void> Function() postActivationRefresh,
  }) async {
    if (password == null || password.isEmpty) {
      throw const BackupPasswordRequiredException();
    }
    final RawBackupInspection result;
    try {
      result = mode == LocalRestoreMode.merge
          ? await _rawMerges.restoreMerge(
              File(filePath),
              password: password,
              onStage: restoreDiagnosticStage,
            )
          : await _rawRestores.restoreReplace(
              File(filePath),
              password: password,
              onStage: restoreDiagnosticStage,
            );
    } on RestoreRecoveryRequiredException {
      // The physical restore journal remains authoritative. Persist a
      // recovery-only UI gate, including when the database cannot reopen;
      // do not let normal financial writes resume on an uncertain file set.
      try {
        await backups.recoveryState.markUnknownRequired(
          operationId: 'raw-restore-${DateTime.now().microsecondsSinceEpoch}',
          reason: 'raw-restore-rollback-incomplete',
        );
      } catch (_) {
        // markUnknownRequired updates in-memory state before attempting disk
        // persistence; preserve the original recovery exception and journal.
      }
      rethrow;
    }
    // The old postActivationRefresh callback installs and validates analysis
    // rules. Do not run business validation as part of restoring raw files.
    // WorkspaceDataService refreshes presentation state after this returns.
    return LocalRestoreResult(
      mode: mode,
      restoredRows: result.recordCount,
      keptNewerLocalRows: 0,
      restoredEvidence: result.attachmentCount,
    );
  }

  @override
  Future<LocalDataExportResult> exportAll() async {
    final result = await data.exportAll();
    return LocalDataExportResult(
      directoryPath: result.directory.path,
      recordCount: result.recordCount,
    );
  }

  @override
  Future<void> eraseAll() async {
    await data.eraseAll();
    // Erase All supersedes any in-memory publication-recovery warning because
    // the private source/previous artifacts and their markers were deleted.
    backups.publicationRecoveryState.clear();
  }

  @override
  Future<void> recoverControlledState({
    required Future<void> Function() postActivationRefresh,
  }) async {
    if (backups.recoveryState.incident?.reason ==
        'raw-restore-rollback-incomplete') {
      await EvidenceMutationLock.runExclusive(() async {
        final persistence = data.database.persistenceDatabase;
        final live = File(persistence.path);
        // A prior rollback may have left the connection open or partially
        // reopened. Acquire the write fence and close it BEFORE touching
        // journaled SQLite paths. A failed close leaves the journal and
        // recovery gate in place; never rename live files in that state.
        if (!persistence.isRestoreActivationActive) {
          persistence.beginRestoreActivation();
        }
        await restoreDiagnosticStage?.call('recovery connection close');
        await persistence.close();
        await restoreDiagnosticStage?.call('recovery connection closed');
        await RawRestoreService.recoverInterruptedReplace(
          liveDatabase: live,
          evidenceDirectory: await data.evidenceDirectory(),
        );
        // Reopen the same persistence object so injected repositories retain
        // their original reference. Keep the gate held until integrity passes.
        await data.database.reopenActiveConnection();
        final integrity = await persistence.restoreActivationConnection
            .rawQuery('PRAGMA integrity_check');
        if (integrity.length != 1 || integrity.single.values.single != 'ok') {
          throw StateError('Recovered SQLite failed physical integrity.');
        }
        await backups.recoveryState.clear();
        persistence.finishRestoreActivation();
        // No legacy rule seeding/business repair during raw journal rollback.
      });
      return;
    }
    await backups.recoverControlledState(
      postActivationRefresh: postActivationRefresh,
    );
  }

  @override
  Future<void> resetControlledRecovery({
    required Future<void> Function() postResetRefresh,
  }) => backups.resetControlledRecovery(postResetRefresh: postResetRefresh);
}
,
  );

  /// Sharing uses the OS temporary root, not the app-support root.
  /// Isolate each share for recovery-aware orphan cleanup after a crash.
  @override
  Future<TemporaryBackupCreationResult> createTemporaryBackup(
    String fileName, {
    required String password,
  }) async {
    final temporary = await getTemporaryDirectory();
    await rejectSymlinkedPath(temporary.path);
    final operationId = DateTime.now().microsecondsSinceEpoch;
    final shareDirectory = Directory(
      path.join(temporary.path, '.butlerly-backup-share-$operationId'),
    );
    await shareDirectory.create();
    final file = File(path.join(shareDirectory.path, path.basename(fileName)));
    try {
      final backup = await _createRawBackup(file, password);
      return TemporaryBackupCreationResult(filePath: file.path, backup: backup);
    } catch (_) {
      await discardTemporaryBackup(file.path);
      rethrow;
    }
  }

  @override
  Future<void> discardTemporaryBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
      final parent = file.parent;
      if (_shareDirectoryName.hasMatch(path.basename(parent.path))) {
        await rejectSymlinkedPath(parent.path);
        if (await parent.exists()) await parent.delete();
      }
    } catch (_) {
      // Best-effort cleanup must not replace the operation's original result.
      // Never recursively remove an unexpected or nonempty directory.
    }
  }

  /// Cold-launch cleanup of crash-orphaned share files. Run only after
  /// portable-publication recovery; an unresolved marker can still refer to
  /// one of these temporary destinations.
  static Future<void> cleanupAbandonedTemporaryShareBackups({
    Directory? temporaryRoot,
    bool publicationRecoveryPending = false,
  }) async {
    if (publicationRecoveryPending) return;
    final root = temporaryRoot ?? await getTemporaryDirectory();
    await rejectSymlinkedPath(root.path);
    if (!await root.exists()) return;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory ||
          !_shareDirectoryName.hasMatch(path.basename(entry.path))) {
        continue;
      }
      try {
        await rejectEvidenceTree(entry);
        await entry.delete(recursive: true);
      } catch (_) {
        // Never follow symlinks or make a healthy startup fail on cleanup.
      }
    }
  }

  @override
  Future<bool> isEncryptedBackup(String filePath) =>
      backups.isEncryptedBackup(File(filePath));

  @override
  Future<BackupInspection> inspect(String filePath, {String? password}) async {
    if (password == null || password.isEmpty) {
      throw const BackupPasswordRequiredException();
    }
    final result = await _rawBackups.inspect(
      File(filePath),
      password: password,
    );
    return BackupInspection(
      createdAtUtc: result.createdAtUtc,
      recordCount: result.recordCount,
      evidenceCount: result.attachmentCount,
      missingEvidenceCount: result.missingAttachmentCount,
      // Raw snapshot inspection never interprets newer local financial rows.
      changes: const BackupChangeSummary(
        transactionsAdded: 0,
        transactionsChanged: 0,
        masterDataChanged: 0,
        deletedEntities: 0,
      ),
    );
  }

  @override
  Future<LocalRestoreResult> restore(
    String filePath, {
    required LocalRestoreMode mode,
    String? password,
    required Future<void> Function() postActivationRefresh,
  }) async {
    if (password == null || password.isEmpty) {
      throw const BackupPasswordRequiredException();
    }
    final RawBackupInspection result;
    try {
      result = mode == LocalRestoreMode.merge
          ? await _rawMerges.restoreMerge(
              File(filePath),
              password: password,
              onStage: restoreDiagnosticStage,
            )
          : await _rawRestores.restoreReplace(
              File(filePath),
              password: password,
              onStage: restoreDiagnosticStage,
            );
    } on RestoreRecoveryRequiredException {
      // The physical restore journal remains authoritative. Persist a
      // recovery-only UI gate, including when the database cannot reopen;
      // do not let normal financial writes resume on an uncertain file set.
      try {
        await backups.recoveryState.markUnknownRequired(
          operationId: 'raw-restore-${DateTime.now().microsecondsSinceEpoch}',
          reason: 'raw-restore-rollback-incomplete',
        );
      } catch (_) {
        // markUnknownRequired updates in-memory state before attempting disk
        // persistence; preserve the original recovery exception and journal.
      }
      rethrow;
    }
    // The old postActivationRefresh callback installs and validates analysis
    // rules. Do not run business validation as part of restoring raw files.
    // WorkspaceDataService refreshes presentation state after this returns.
    return LocalRestoreResult(
      mode: mode,
      restoredRows: result.recordCount,
      keptNewerLocalRows: 0,
      restoredEvidence: result.attachmentCount,
    );
  }

  @override
  Future<LocalDataExportResult> exportAll() async {
    final result = await data.exportAll();
    return LocalDataExportResult(
      directoryPath: result.directory.path,
      recordCount: result.recordCount,
    );
  }

  @override
  Future<void> eraseAll() async {
    await data.eraseAll();
    // Erase All supersedes any in-memory publication-recovery warning because
    // the private source/previous artifacts and their markers were deleted.
    backups.publicationRecoveryState.clear();
  }

  @override
  Future<void> recoverControlledState({
    required Future<void> Function() postActivationRefresh,
  }) async {
    if (backups.recoveryState.incident?.reason ==
        'raw-restore-rollback-incomplete') {
      await EvidenceMutationLock.runExclusive(() async {
        final persistence = data.database.persistenceDatabase;
        final live = File(persistence.path);
        // A prior rollback may have left the connection open or partially
        // reopened. Acquire the write fence and close it BEFORE touching
        // journaled SQLite paths. A failed close leaves the journal and
        // recovery gate in place; never rename live files in that state.
        if (!persistence.isRestoreActivationActive) {
          persistence.beginRestoreActivation();
        }
        await restoreDiagnosticStage?.call('recovery connection close');
        await persistence.close();
        await restoreDiagnosticStage?.call('recovery connection closed');
        await RawRestoreService.recoverInterruptedReplace(
          liveDatabase: live,
          evidenceDirectory: await data.evidenceDirectory(),
        );
        // Reopen the same persistence object so injected repositories retain
        // their original reference. Keep the gate held until integrity passes.
        await data.database.reopenActiveConnection();
        final integrity = await persistence.restoreActivationConnection
            .rawQuery('PRAGMA integrity_check');
        if (integrity.length != 1 || integrity.single.values.single != 'ok') {
          throw StateError('Recovered SQLite failed physical integrity.');
        }
        await backups.recoveryState.clear();
        persistence.finishRestoreActivation();
        // No legacy rule seeding/business repair during raw journal rollback.
      });
      return;
    }
    await backups.recoverControlledState(
      postActivationRefresh: postActivationRefresh,
    );
  }

  @override
  Future<void> resetControlledRecovery({
    required Future<void> Function() postResetRefresh,
  }) => backups.resetControlledRecovery(postResetRefresh: postResetRefresh);
}
