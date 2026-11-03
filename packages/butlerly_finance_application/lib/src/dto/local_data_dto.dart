enum LocalRestoreMode { merge, replace }

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
  });

  final DateTime createdAtUtc;
  final int recordCount;
  final int evidenceCount;
  final BackupChangeSummary changes;

  bool get hasNewerLocalData => changes.hasChanges;
}

final class LocalRestoreResult {
  const LocalRestoreResult({
    required this.mode,
    required this.restoredRows,
    required this.keptNewerLocalRows,
    required this.restoredEvidence,
    this.presentationRefreshFailed = false,
  });

  final LocalRestoreMode mode;
  final int restoredRows;
  final int keptNewerLocalRows;
  final int restoredEvidence;

  /// The database restore succeeded, but the non-critical UI refresh failed.
  /// Do not report this as a failed data restore or try to restore again.
  final bool presentationRefreshFailed;
}

/// Result of an explicitly approved evidence-file recovery operation.
///
/// Recovery is deliberately scoped to files referenced by the current local
/// database. It never changes SQLite rows or analysis state. Existing files
/// are verified and left untouched; only missing files whose bytes are present
/// and valid in the selected backup are added.
final class EvidenceRecoveryResult {
  const EvidenceRecoveryResult({
    required this.recoveredCount,
    required this.alreadyPresentCount,
    required this.unresolvedCount,
    this.conflictingCount = 0,
    this.unavailableCount = 0,
  });

  final int recoveredCount;
  final int alreadyPresentCount;
  final int unresolvedCount;
  final int conflictingCount;
  final int unavailableCount;

  bool get isComplete => unresolvedCount == 0;
}

/// Read-only evidence recovery assessment produced before any file is
/// published. The fingerprint is opaque to presentation and binds the
/// confirmation step to the exact current database/archive assessment.
final class EvidenceRecoveryPreview {
  const EvidenceRecoveryPreview({
    required this.recoverableCount,
    required this.alreadyPresentCount,
    required this.conflictingCount,
    required this.unavailableCount,
    required this.unresolvedCount,
    required this.fingerprint,
  });

  final int recoverableCount;
  final int alreadyPresentCount;
  final int conflictingCount;
  final int unavailableCount;
  final int unresolvedCount;
  final String fingerprint;

  bool get isComplete => unresolvedCount == 0;
}

/// The live evidence references changed after preview and before confirmation.
final class EvidenceRecoveryPreviewStaleException implements Exception {
  const EvidenceRecoveryPreviewStaleException();
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
