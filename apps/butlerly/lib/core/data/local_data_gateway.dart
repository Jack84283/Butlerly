import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/raw_backup_archive.dart';
import 'package:butlerly/core/data/raw_backup_service.dart';
import 'package:butlerly/core/data/raw_merge_service.dart';
import 'package:butlerly/core/data/raw_restore_service.dart';
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

  @override
  Future<TemporaryBackupCreationResult> createTemporaryBackup(
    String fileName, {
    required String password,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File(path.join(directory.path, path.basename(fileName)));
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
    } catch (_) {
      // Best-effort cleanup must not replace the operation's original result.
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
      final persistence = data.database.persistenceDatabase;
      final live = File(persistence.path);
      await RawRestoreService.recoverInterruptedReplace(
        liveDatabase: live,
        evidenceDirectory: await data.evidenceDirectory(),
      );
      // Reuse the repository-owned persistence object after physical
      // recovery. Never replace it with a new object that would leave
      // existing financial repositories referencing stale connections.
      await data.database.reopenActiveConnection();
      final activeConnection = persistence.isRestoreActivationActive
          ? persistence.restoreActivationConnection
          : persistence.connection;
      final integrity = await activeConnection.rawQuery(
        'PRAGMA integrity_check',
      );
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw StateError('Recovered SQLite failed physical integrity.');
      }
      await backups.recoveryState.clear();
      persistence.finishRestoreActivation();
      await postActivationRefresh();
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
