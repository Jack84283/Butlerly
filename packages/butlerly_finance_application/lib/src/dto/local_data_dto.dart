import 'data_integrity_dto.dart';

enum LocalRestoreMode { merge, replace }

/// A privacy-safe condition observed while creating or restoring a backup.
///
/// These warnings describe source data that could not be copied or derived
/// data that will be rebuilt. They never contain paths, exception text, or
/// financial values.
final class BackupWarning {
  const BackupWarning({
    required this.code,
    required this.count,
    this.affectedRecords = const [],
  });

  final String code;
  final int count;
  final List<DataIntegrityRecordReference> affectedRecords;
}

final class BackupChangeSummary {
  const BackupChangeSummary({
    required this.transactionsAdded,
    required this.transactionsChanged,
    required this.masterDataChanged,
    required this.deletedEntities,
  });

  final int transactionsAdded;
  final int transactionsChanged;
  final int masterDataChanged;
  final int deletedEntities;

  bool get hasChanges =>
      transactionsAdded > 0 ||
      transactionsChanged > 0 ||
      masterDataChanged > 0 ||
      deletedEntities > 0;
}

final class BackupInspection {
  const BackupInspection({
    required this.createdAtUtc,
    required this.recordCount,
    required this.evidenceCount,
    required this.changes,
    this.warnings = const [],
    this.missingContentCount = 0,
  });

  final DateTime createdAtUtc;
  final int recordCount;
  final int evidenceCount;
  final BackupChangeSummary changes;
  final List<BackupWarning> warnings;
  final int missingContentCount;

  bool get hasNewerLocalData => changes.hasChanges;
}

final class LocalRestoreResult {
  const LocalRestoreResult({
    required this.mode,
    required this.restoredRows,
    required this.keptNewerLocalRows,
    required this.restoredEvidence,
    this.preservesUnresolvedReferences = false,
    this.presentationRefreshFailed = false,
    this.analysisRebuildFailed = false,
    this.warnings = const [],
  });

  final LocalRestoreMode mode;
  final int restoredRows;
  final int keptNewerLocalRows;
  final int restoredEvidence;

  /// The archive intentionally preserves source rows whose optional targets
  /// are unavailable. The standalone data-integrity report remains the owner
  /// of explaining those relationships.
  final bool preservesUnresolvedReferences;

  /// The database restore succeeded, but the non-critical UI refresh failed.
  /// Do not report this as a failed data restore or try to restore again.
  final bool presentationRefreshFailed;

  /// The primary restore committed, but rebuilding derived analysis state
  /// could not complete. Source data remains restored and is safe to inspect.
  final bool analysisRebuildFailed;

  final List<BackupWarning> warnings;
}

final class LocalDataExportResult {
  const LocalDataExportResult({
    required this.directoryPath,
    required this.recordCount,
  });
  final String directoryPath;
  final int recordCount;
}

final class BackupPasswordRequiredException implements Exception {
  const BackupPasswordRequiredException();
}

final class BackupPasswordTooShortException implements Exception {
  const BackupPasswordTooShortException();
}

final class BackupPasswordOrIntegrityException implements Exception {
  const BackupPasswordOrIntegrityException();
}

/// Raised when an encrypted backup cannot be produced or verified.
final class BackupEncryptionException implements Exception {
  const BackupEncryptionException();
}

/// Raised when a portable backup publication entered controlled recovery.
///
/// This intentionally carries no filesystem paths or adapter-specific
/// recovery payload. The recovery surface reads its state through the normal
/// application flow.
final class BackupPublicationRecoveryException implements Exception {
  const BackupPublicationRecoveryException();
}

final class RestoreRecoveryRequiredException implements Exception {
  const RestoreRecoveryRequiredException();
}

/// Product-level portable-backup policy shared by application and adapters.
abstract final class PortableBackupPolicy {
  static const minimumPasswordLength = 12;

  /// User-visible portable backup suffix. Keep [legacyExtension] accepted by
  /// file pickers so backups created before the V1 suffix correction remain
  /// restorable.
  static const extension = 'butlerly';
  static const legacyExtension = 'butlerlybackup';
  static const uniformTypeIdentifier = 'com.butlerly.backup';
  static const mimeType = 'application/vnd.butlerly.backup';
}
