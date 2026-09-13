import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:flutter/foundation.dart';

final class RestoreRecoveryIncident {
  const RestoreRecoveryIncident({
    required this.operationId,
    required this.safetyBackupPath,
    required this.reason,
    required this.retryCurrentState,
  });

  final String operationId;
  final String safetyBackupPath;
  final String reason;

  /// True only when the restore engine committed a coherent candidate and the
  /// remaining uncertainty is post-activation validation/runtime refresh.
  /// Recovery may validate and keep that live state before considering the
  /// safety snapshot.
  final bool retryCurrentState;
}

/// Persistent, process-visible gate for a restore whose final state has not yet
/// been proven safe for ordinary application writes.
final class RestoreRecoveryState extends ChangeNotifier {
  RestoreRecoveryState(this.localDataManager);

  final LocalDataManager localDataManager;

  RestoreRecoveryIncident? _incident;

  RestoreRecoveryIncident? get incident => _incident;
  bool get isRecoveryRequired => _incident != null;

  Future<void> initialize() async {
    _incident = null;
    final marker = await _markerFile();
    final temporary = File('${marker.path}.tmp');
    final previous = File('${marker.path}.previous');
    final markerExists = await marker.exists();
    final temporaryExists = await temporary.exists();
    final previousExists = await previous.exists();

    if (!markerExists) {
      if (temporaryExists || previousExists) {
        _setGenericIncident('recovery-marker-interrupted');
      }
      return;
    }

    // A main marker plus a new .tmp means replacement started but never reached
    // its atomic rename. The main file can therefore describe an older incident;
    // do not automatically recover from it. A main marker plus only .previous
    // means the rename completed and cleanup was interrupted, so main is current.
    if (temporaryExists) {
      _setGenericIncident('recovery-marker-interrupted');
      return;
    }

    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map) {
        throw const FormatException('Invalid recovery marker payload.');
      }
      final data = decoded.cast<String, Object?>();
      final operationId = data['operationId'];
      final safetyBackupPath = data['safetyBackupPath'];
      final reason = data['reason'];
      final retryCurrentState = data['retryCurrentState'];
      if (operationId is! String ||
          operationId.isEmpty ||
          safetyBackupPath is! String ||
          reason is! String ||
          reason.isEmpty ||
          (retryCurrentState != null && retryCurrentState is! bool)) {
        throw const FormatException('Incomplete recovery marker payload.');
      }
      _incident = RestoreRecoveryIncident(
        operationId: operationId,
        safetyBackupPath: safetyBackupPath,
        reason: reason,
        retryCurrentState: retryCurrentState as bool? ?? false,
      );
      notifyListeners();
      if (previousExists) {
        try {
          await previous.delete();
        } catch (_) {
          // Main marker is already authoritative; stale rollback cleanup is best effort.
        }
      }
    } on Exception {
      _setGenericIncident('recovery-marker-unreadable');
    }
  }

  Future<void> markRequired({
    required String operationId,
    required File safetyBackup,
    required String reason,
    bool retryCurrentState = false,
  }) => _persistIncident(
    RestoreRecoveryIncident(
      operationId: operationId,
      safetyBackupPath: safetyBackup.path,
      reason: reason,
      retryCurrentState: retryCurrentState,
    ),
  );

  Future<void> markUnknownRequired({
    required String operationId,
    required String reason,
  }) => _persistIncident(
    RestoreRecoveryIncident(
      operationId: operationId.isEmpty ? 'unknown' : operationId,
      safetyBackupPath: '',
      reason: reason,
      retryCurrentState: false,
    ),
  );

  Future<void> _persistIncident(RestoreRecoveryIncident incident) async {
    _incident = incident;
    notifyListeners();

    final marker = await _markerFile();
    await marker.parent.create(recursive: true);
    final temporary = File('${marker.path}.tmp');
    final previous = File('${marker.path}.previous');

    await temporary.writeAsString(
      jsonEncode({
        'operationId': incident.operationId,
        'safetyBackupPath': incident.safetyBackupPath,
        'reason': incident.reason,
        'retryCurrentState': incident.retryCurrentState,
      }),
      flush: true,
    );

    if (await previous.exists()) await previous.delete();
    if (await marker.exists()) await marker.rename(previous.path);
    try {
      await temporary.rename(marker.path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      rethrow;
    }
  }

  Future<void> clear() async {
    final marker = await _markerFile();
    for (final file in <File>[
      marker,
      File('${marker.path}.tmp'),
      File('${marker.path}.previous'),
    ]) {
      if (await file.exists()) await file.delete();
    }
    _incident = null;
    notifyListeners();
  }

  void _setGenericIncident(String reason) {
    _incident = RestoreRecoveryIncident(
      operationId: 'unknown',
      safetyBackupPath: '',
      reason: reason,
      retryCurrentState: false,
    );
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
