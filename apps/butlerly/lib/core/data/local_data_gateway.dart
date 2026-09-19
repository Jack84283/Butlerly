import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Local adapter for application-owned privacy and recovery operations.
final class LocalWorkspaceDataGateway implements LocalDataGateway {
  const LocalWorkspaceDataGateway(this.backups, this.data);
  final LocalBackupManager backups;
  final LocalDataManager data;

  @override
  bool get hasRecoverySafetyCopy =>
      backups.recoveryState.incident?.safetyBackupPath.isNotEmpty == true;

  @override
  Future<void> createPortableBackup(
    String destination, {
    required String password,
  }) async {
    await backups.createPortableBackup(File(destination), password: password);
  }

  @override
  Future<String> createTemporaryBackup(
    String fileName, {
    required String password,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File(path.join(directory.path, path.basename(fileName)));
    try {
      await backups.createPortableBackup(file, password: password);
      return file.path;
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
  Future<BackupInspection> inspect(String filePath, {String? password}) =>
      backups.inspect(File(filePath), password: password);

  @override
  Future<LocalRestoreResult> restore(
    String filePath, {
    required LocalRestoreMode mode,
    String? password,
    required Future<void> Function() postActivationRefresh,
  }) => backups.restore(
    File(filePath),
    mode: mode,
    password: password,
    postActivationRefresh: postActivationRefresh,
  );

  @override
  Future<LocalDataExportResult> exportAll() async {
    final result = await data.exportAll();
    return LocalDataExportResult(
      directoryPath: result.directory.path,
      recordCount: result.recordCount,
    );
  }

  @override
  Future<void> eraseAll() => data.eraseAll();

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
