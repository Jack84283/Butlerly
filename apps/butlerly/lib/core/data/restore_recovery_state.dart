import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:flutter/foundation.dart';

final class RestoreRecoveryIncident {
  const RestoreRecoveryIncident({
    required this.operationId,
    required this.safetyBackupPath,
    required this.reason,
  });

  final String operationId;
  final String safetyBackupPath;
  final String reason;
}

/// Persistent, process-visible gate for a restore whose rollback could not be
/// proven complete.
///
/// The marker lives outside SQLite so it remains readable even when database
/// state itself is uncertain. Presentation observes this object and replaces
/// the normal product UI with recovery-only actions until a validated safety
/// snapshot has been restored successfully.
final class RestoreRecoveryState extends ChangeNotifier {
  RestoreRecoveryState(this.localDataManager);

  final LocalDataManager localDataManager;

  RestoreRecoveryIncident? _incident;

  RestoreRecoveryIncident? get incident => _incident;
  bool get isRecoveryRequired => _incident != null;

  Future<void> initialize() async {
    final marker = await _markerFile();
    if (!await marker.exists()) return;
    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map) return;
      final data = decoded.cast<String, Object?>();
      final operationId = data['operationId'] as String?;
      final safetyBackupPath = data['safetyBackupPath'] as String?;
      final reason = data['reason'] as String?;
      if (operationId == null || safetyBackupPath == null || reason == null) {
        return;
      }
      _incident = RestoreRecoveryIncident(
        operationId: operationId,
        safetyBackupPath: safetyBackupPath,
        reason: reason,
      );
      notifyListeners();
    } on Exception {
      // A malformed marker must fail closed. Preserve it and expose a generic
      // incident rather than silently resuming normal financial writes.
      _incident = const RestoreRecoveryIncident(
        operationId: 'unknown',
        safetyBackupPath: '',
        reason: 'recovery-marker-unreadable',
      );
      notifyListeners();
    }
  }

  Future<void> markRequired({
    required String operationId,
    required File safetyBackup,
    required String reason,
  }) async {
    final marker = await _markerFile();
    await marker.parent.create(recursive: true);
    final temporary = File('${marker.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'operationId': operationId,
        'safetyBackupPath': safetyBackup.path,
        'reason': reason,
      }),
      flush: true,
    );
    if (await marker.exists()) await marker.delete();
    await temporary.rename(marker.path);
    _incident = RestoreRecoveryIncident(
      operationId: operationId,
      safetyBackupPath: safetyBackup.path,
      reason: reason,
    );
    notifyListeners();
  }

  Future<void> clear() async {
    final marker = await _markerFile();
    if (await marker.exists()) await marker.delete();
    _incident = null;
    notifyListeners();
  }

  Future<File> _markerFile() async {
    final evidence = await localDataManager.evidenceDirectory();
    return File('${evidence.path}.restore-recovery-required.json');
  }
}

final class RestoreRecoveryRequiredException implements Exception {
  const RestoreRecoveryRequiredException();
}
