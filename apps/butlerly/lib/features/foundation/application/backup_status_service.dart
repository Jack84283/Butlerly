import 'package:butlerly/core/data/local_backup_status_store.dart';
export 'package:butlerly/core/data/local_backup_status_store.dart' show LocalBackupStatus;

/// Application-facing contract for optional local backup completion metadata.
/// This is not evidence that an exported file is still recoverable.
abstract interface class BackupStatusService {
  Future<LocalBackupStatus?> read();
  Future<void> recordCompleted({required bool missingAttachments});
}

final class LocalBackupStatusService implements BackupStatusService {
  const LocalBackupStatusService({LocalBackupStatusStore? store})
    : _store = store ?? const LocalBackupStatusStore();

  final LocalBackupStatusStore _store;

  @override
  Future<LocalBackupStatus?> read() => _store.read();

  @override
  Future<void> recordCompleted({required bool missingAttachments}) =>
      _store.recordCompleted(missingAttachments: missingAttachments);
}
