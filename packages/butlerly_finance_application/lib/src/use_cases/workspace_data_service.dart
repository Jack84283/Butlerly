import '../dto/local_data_dto.dart';
import '../analysis/invalidation.dart';

/// Storage port. File handles, SQLite executors, and platform SDKs stay in the
/// adapter; presentation exchanges selected paths and immutable result values.
abstract interface class LocalDataGateway {
  bool get hasRecoverySafetyCopy;
  Future<void> createPortableBackup(
    String destination, {
    required String password,
  });
  Future<void> recoverPortableBackupPublication(String destination);
  Future<void> dismissPortableBackupPublicationRecovery();
  Future<String> createTemporaryBackup(
    String fileName, {
    required String password,
  });
  Future<void> discardTemporaryBackup(String filePath);
  Future<bool> isEncryptedBackup(String filePath);
  Future<BackupInspection> inspect(String filePath, {String? password});
  Future<EvidenceRecoveryPreview> inspectMissingEvidence(
    String filePath, {
    String? password,
  });
  Future<EvidenceRecoveryResult> recoverMissingEvidence(
    String filePath, {
    String? password,
    required EvidenceRecoveryPreview preview,
  });
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

/// Raised when a portable backup contains invalid analysis-rule state.
///
/// Presentation code can use this application-level contract to offer the
/// explicit rule-repair operation only for a failure attributable to rule
/// validation, without depending on a storage adapter.
final class BackupAnalysisRuleValidationException extends FormatException {
  const BackupAnalysisRuleValidationException(
    super.message, {
    this.canRepair = false,
  });

  /// Whether the persisted failure is known to be repairable by restoring
  /// bundled definitions and activations.
  final bool canRepair;

  @override
  String toString() => 'BackupAnalysisRuleValidationException: $message';
}

/// Raised when a validated backup cannot be published to device storage.
///
/// The adapter deliberately exposes no path or filesystem details so the
/// presentation layer can report the correct category without leaking
/// private storage information.
final class BackupStorageException implements Exception {
  const BackupStorageException();
}

/// Raised when backup creation fails outside a known product-level category.
///
/// Only the safe operation stage and exception type cross the application
/// boundary. Exception messages and stack traces may contain private paths,
/// platform payloads, or financial data and must remain in privacy-safe logs.
final class BackupFailureException extends FormatException {
  const BackupFailureException({required this.stage, required this.errorType})
    : super('Portable backup creation failed.');

  /// The bounded backup stage reported by the storage adapter.
  final String stage;

  /// The exception class name, without its message or payload.
  final String errorType;
}

/// Raised when restore fails outside a known password or recovery category.
///
/// Only the safe operation stage and exception type cross the application
/// boundary. Exception messages and stack traces may contain private paths,
/// platform payloads, or financial data and must remain in privacy-safe logs.
final class RestoreFailureException extends FormatException {
  const RestoreFailureException({required this.stage, required this.errorType})
    : super('Backup restore failed.');

  /// The bounded restore stage reported by the storage adapter.
  final String stage;

  /// The exception class name, without its message or payload.
  final String errorType;
}

/// Application orchestration shared by normal privacy controls and recovery.
/// System-data refresh must complete inside the adapter's restore safety gate.
/// UI invalidation must wait until restore commits and closes its recovery gate.
final class WorkspaceDataService {
  const WorkspaceDataService(
    this.gateway, {
    required this.refreshSystemData,
    this.repairAnalysisRulesCallback,
    this.consistencyGate,
  });
  final LocalDataGateway gateway;
  final Future<void> Function() refreshSystemData;

  /// Explicitly repairs the installed bundled analysis rules.
  ///
  /// Backup creation deliberately does not call this callback. A backup is a
  /// protective read-only operation against live financial data; callers must
  /// obtain user approval before invoking a repair.
  final Future<void> Function()? repairAnalysisRulesCallback;
  final AnalysisConsistencyGate? consistencyGate;

  bool get hasRecoverySafetyCopy => gateway.hasRecoverySafetyCopy;

  Future<void> createPortableBackup(
    String destination, {
    required String password,
  }) => _runConsistently(
    () => gateway.createPortableBackup(destination, password: password),
  );
  Future<void> recoverPortableBackupPublication(String destination) =>
      gateway.recoverPortableBackupPublication(destination);
  Future<void> dismissPortableBackupPublicationRecovery() =>
      gateway.dismissPortableBackupPublicationRecovery();
  Future<String> createTemporaryBackup(
    String fileName, {
    required String password,
  }) => _runConsistently(
    () => gateway.createTemporaryBackup(fileName, password: password),
  );

  /// Runs the separately approved analysis-rule repair operation.
  Future<void> repairAnalysisRules() => _runConsistently(() async {
    final repair = repairAnalysisRulesCallback;
    if (repair == null) {
      throw StateError('Bundled analysis rule repair is unavailable.');
    }
    await repair();
  });
  Future<void> discardTemporaryBackup(String filePath) =>
      gateway.discardTemporaryBackup(filePath);
  Future<bool> isEncryptedBackup(String filePath) =>
      gateway.isEncryptedBackup(filePath);
  Future<BackupInspection> inspect(String filePath, {String? password}) =>
      gateway.inspect(filePath, password: password);
  Future<EvidenceRecoveryPreview> inspectMissingEvidence(
    String filePath, {
    String? password,
  }) => _runConsistently(
    () => gateway.inspectMissingEvidence(filePath, password: password),
  );
  Future<EvidenceRecoveryResult> recoverMissingEvidence(
    String filePath, {
    String? password,
    required EvidenceRecoveryPreview preview,
  }) => _runConsistently(
    () => gateway.recoverMissingEvidence(
      filePath,
      password: password,
      preview: preview,
    ),
  );
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
  }) => _runConsistently(() async {
    final result = await gateway.restore(
      filePath,
      mode: mode,
      password: password,
      // Keep validation/reseeding inside the restore safety gate, but do not
      // invalidate mounted screens while activation/cleanup is still running.
      postActivationRefresh: () => _refresh(null),
    );
    try {
      await refreshPresentation?.call();
      return result;
    } catch (_) {
      // Persistence has already committed. The caller must not interpret a
      // presentation refresh failure as a failed backup restore.
      return LocalRestoreResult(
        mode: result.mode,
        restoredRows: result.restoredRows,
        keptNewerLocalRows: result.keptNewerLocalRows,
        restoredEvidence: result.restoredEvidence,
        presentationRefreshFailed: true,
      );
    }
  });

  Future<void> eraseAll({Future<void> Function()? refreshPresentation}) =>
      _runConsistently(() async {
        await gateway.eraseAll();
        await _refresh(refreshPresentation);
      });

  Future<void> recoverControlledState({
    Future<void> Function()? refreshPresentation,
  }) => _runConsistently(
    () => gateway.recoverControlledState(
      postActivationRefresh: () => _refresh(refreshPresentation),
    ),
  );

  Future<void> resetControlledRecovery({
    Future<void> Function()? refreshPresentation,
  }) => _runConsistently(
    () => gateway.resetControlledRecovery(
      postResetRefresh: () => _refresh(refreshPresentation),
    ),
  );

  Future<T> _runConsistently<T>(Future<T> Function() operation) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}
