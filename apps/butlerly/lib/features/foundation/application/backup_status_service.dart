import 'package:butlerly/core/data/local_backup_status_store.dart';

/// Application projection, separate from the platform persistence adapter.
final class BackupStatusRecord {
  const BackupStatusRecord({
    required this.completedAtUtc,
    required this.missingAttachments,
  });

  final DateTime completedAtUtc;
  final bool missingAttachments;
}

/// Optional local metadata: a created backup is not a verified restore.
abstract interface class BackupStatusService {
  Future<BackupStatusRecord?> read();
  Future<void> recordCompleted({required bool missingAttachments});
}

final class LocalBackupStatusService implements BackupStatusService {
  const LocalBackupStatusService({LocalBackupStatusStore? store})
    : _store = store ?? const LocalBackupStatusStore();

  final LocalBackupStatusStore _store;

  @override
  Future<BackupStatusRecord?> read() async {
    final record = await _store.read();
    if (record == null) return null;
    return BackupStatusRecord(
      completedAtUtc: record.completedAtUtc,
      missingAttachments: record.missingAttachments,
    );
  }

  @override
  Future<void> recordCompleted({required bool missingAttachments}) =>
      _store.recordCompleted(missingAttachments: missingAttachments);
}
