import '../dto/local_data_dto.dart';

/// Storage port. File handles, SQLite executors, and platform SDKs stay in the
/// adapter; presentation exchanges selected paths and immutable result values.
abstract interface class LocalDataGateway {
  bool get hasRecoverySafetyCopy;
  Future<void> createPortableBackup(
    String destination, {
    required String password,
  });
  Future<String> createTemporaryBackup(
    String fileName, {
    required String password,
  });
  Future<void> discardTemporaryBackup(String filePath);
  Future<bool> isEncryptedBackup(String filePath);
  Future<BackupInspection> inspect(String filePath, {String? password});
  Future<LocalRestoreResult> restore(
    String filePath, {
    required LocalRestoreMode mode,
    String? password,
    required Future<void> Function() postActivationRefresh,
  });
  Future<LocalDataExportResult> exportAll();
  Future<void> eraseAll();
  Future<void> recoverControlledState({
    required Future<void> Function() postActivationRefresh,
  });
  Future<void> resetControlledRecovery({
    required Future<void> Function() postResetRefresh,
  });
}

/// Application orchestration shared by normal privacy controls and recovery.
/// System-data refresh must complete inside the adapter's restore safety gate.
final class WorkspaceDataService {
  const WorkspaceDataService(this.gateway, {required this.refreshSystemData});
  final LocalDataGateway gateway;
  final Future<void> Function() refreshSystemData;

  bool get hasRecoverySafetyCopy => gateway.hasRecoverySafetyCopy;

  Future<void> createPortableBackup(
    String destination, {
    required String password,
  }) => gateway.createPortableBackup(destination, password: password);
  Future<String> createTemporaryBackup(
    String fileName, {
    required String password,
  }) => gateway.createTemporaryBackup(fileName, password: password);
  Future<void> discardTemporaryBackup(String filePath) =>
      gateway.discardTemporaryBackup(filePath);
  Future<bool> isEncryptedBackup(String filePath) =>
      gateway.isEncryptedBackup(filePath);
  Future<BackupInspection> inspect(String filePath, {String? password}) =>
      gateway.inspect(filePath, password: password);
  Future<LocalDataExportResult> exportAll() => gateway.exportAll();

  Future<void> _refresh(Future<void> Function()? refreshPresentation) async {
    await refreshSystemData();
    await refreshPresentation?.call();
  }

  Future<LocalRestoreResult> restore(
    String filePath, {
    required LocalRestoreMode mode,
    String? password,
    Future<void> Function()? refreshPresentation,
  }) => gateway.restore(
    filePath,
    mode: mode,
    password: password,
    postActivationRefresh: () => _refresh(refreshPresentation),
  );

  Future<void> eraseAll({Future<void> Function()? refreshPresentation}) async {
    await gateway.eraseAll();
    await _refresh(refreshPresentation);
  }

  Future<void> recoverControlledState({
    Future<void> Function()? refreshPresentation,
  }) => gateway.recoverControlledState(
    postActivationRefresh: () => _refresh(refreshPresentation),
  );

  Future<void> resetControlledRecovery({
    Future<void> Function()? refreshPresentation,
  }) => gateway.resetControlledRecovery(
    postResetRefresh: () => _refresh(refreshPresentation),
  );
}
