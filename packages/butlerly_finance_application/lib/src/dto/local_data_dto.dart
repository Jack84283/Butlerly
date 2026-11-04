/// The point at which an encrypted backup could not be created or delivered.
/// A stage is diagnostic only, and never carries private paths or financial data.
enum BackupCreationStage {
  snapshot,
  inventory,
  packaging,
  encryption,
  verification,
  publication,
  sharing,
}

/// Exposes a safe creation stage without converting an underlying failure to a
/// success. Only an explicitly identified unresolved publication/rollback
/// state should set [recoveryRequired].
final class BackupCreationException implements Exception {
  const BackupCreationException({
    required this.stage,
    required this.cause,
    this.recoveryRequired = false,
  });

  final BackupCreationStage stage;
  final Object cause;
  final bool recoveryRequired;
}

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

final class LocalDataExportResult {
  const LocalDataExportResult({
    required this.directoryPath,
    required this.recordCount,
  });
  final String directoryPath;
  final int recordCount;
}

/// A backup SQLite schema is invalid or unsupported by the installed app.
/// Restoring must stop before any live data is changed.
final class UnsupportedBackupSchemaException extends FormatException {
  const UnsupportedBackupSchemaException()
    : super('Unsupported SQLite backup schema version.');
}

/// The backup was created with a newer database schema than this app supports.
///
/// This error belongs to the application contract so presentation never needs
/// to depend on the SQLite adapter to explain an app-update requirement.
final class NewerBackupSchemaException
    extends UnsupportedBackupSchemaException {
  const NewerBackupSchemaException({
    required this.backupVersion,
    required this.supportedVersion,
  });

  final int backupVersion;
  final int supportedVersion;
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
