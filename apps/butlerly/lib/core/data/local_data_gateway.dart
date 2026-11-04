import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/raw_backup_service.dart';
import 'package:butlerly/core/data/raw_merge_service.dart';
import 'package:butlerly/core/data/raw_restore_service.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Local adapter for application-owned privacy and recovery operations.
final class LocalWorkspaceDataGateway implements LocalDataGateway {
  LocalWorkspaceDataGateway(this.backups, this.data) {
    _rawBackups = RawBackupService(data.database, data);
    _rawRestores = RawRestoreService(data.database, _rawBackups);
    _rawMerges = RawMergeService(data.database, _rawBackups, _rawRestores);
  }

  final LocalBackupManager backups;
  final LocalDataManager data;
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
      return TemporaryBackupCreationResult(
        filePath: file.path,
        backup: backup,
      );
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
    final result = mode == LocalRestoreMode.merge
        ? await _rawMerges.restoreMerge(File(filePath), password: password)
        : await _rawRestores.restoreReplace(File(filePath), password: password);
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
  }) => backups.recoverControlledState(
    postActivationRefresh: postActivationRefresh,
  );

  @override
  Future<void> resetControlledRecovery({
    required Future<void> Function() postResetRefresh,
  }) => backups.resetControlledRecovery(postResetRefresh: postResetRefresh);
}
