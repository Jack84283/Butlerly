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
///
/// The marker lives outside SQLite so it remains readable even when database
/// state itself is uncertain. Presentation observes this object and replaces
/// the normal product UI with recovery-only actions until validation or a
/// retained safety snapshot establishes one coherent state.
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

    if (!await marker.exists()) {
      if (await temporary.exists() || await previous.exists()) {
        _setGenericIncident('recovery-marker-interrupted');
      }
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
    } on Exception {
      // Any existing but malformed/incomplete marker must fail closed. Preserve
      // all marker artifacts so later recovery or diagnostics can inspect them.
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
    // Fail closed in-process before touching disk. Even if persistence itself
    // fails, normal writes remain blocked for the rest of this process.
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
      // Leave .tmp and/or .previous in place. initialize() treats either as a
      // recovery-required sentinel, so a crash during replacement cannot reopen
      // normal financial writes on the next launch.
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
