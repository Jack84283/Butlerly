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
  });

  final LocalRestoreMode mode;
  final int restoredRows;
  final int keptNewerLocalRows;
  final int restoredEvidence;
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

final class RestoreRecoveryRequiredException implements Exception {
  const RestoreRecoveryRequiredException();
}

/// Product-level portable-backup policy shared by application and adapters.
abstract final class PortableBackupPolicy {
  static const minimumPasswordLength = 12;
  static const extension = 'butlerlybackup';
  static const uniformTypeIdentifier = 'com.butlerly.backup';
  static const mimeType = 'application/vnd.butlerly.backup';
}
