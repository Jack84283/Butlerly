import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/application/restore_recovery_status.dart';
import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

export 'package:butlerly/core/application/restore_recovery_status.dart'
    show RestoreRecoveryDiagnostic, RestoreRecoveryStatus;
export 'package:butlerly_finance_application/butlerly_finance_application.dart'
    show RestoreRecoveryRequiredException;

final class RestoreRecoveryIncident {
  const RestoreRecoveryIncident({
    required this.operationId,
    required this.safetyBackupPath,
    required this.reason,
    required this.retryCurrentState,
    this.diagnostic,
  });

  final String operationId;
  final String safetyBackupPath;
  final String reason;

  /// True only when the restore engine committed a coherent candidate and the
  /// remaining uncertainty is post-activation validation/runtime refresh.
  /// Recovery may validate and keep that live state before considering the
  /// safety snapshot.
  final bool retryCurrentState;

  final RestoreRecoveryDiagnostic? diagnostic;
}

/// Persistent, process-visible gate for a restore whose final state has not yet
/// been proven safe for ordinary application writes.
final class RestoreRecoveryState extends ChangeNotifier
    implements RestoreRecoveryStatus {
  RestoreRecoveryState(this.localDataManager);

  final LocalDataManager localDataManager;

  RestoreRecoveryIncident? _incident;
  RestoreRecoveryDiagnostic? _diagnostic;

  RestoreRecoveryIncident? get incident => _incident;
  @override
  bool get isRecoveryRequired => _incident != null;
  @override
  RestoreRecoveryDiagnostic? get diagnostic => _diagnostic;

  /// Updates transient bounded detail for the recovery surface without
  /// changing the persistent recovery gate.
  void setDiagnostic(RestoreRecoveryDiagnostic? diagnostic) {
    _diagnostic = diagnostic?.sanitized;
    final current = _incident;
    if (current != null) {
      _incident = RestoreRecoveryIncident(
        operationId: current.operationId,
        safetyBackupPath: current.safetyBackupPath,
        reason: current.reason,
        retryCurrentState: current.retryCurrentState,
        diagnostic: _diagnostic,
      );
    }
    notifyListeners();
  }

  Future<void> initialize() async {
    _incident = null;
    _diagnostic = null;
    final marker = await _markerFile();
    await rejectSymlinkedPath(marker.path);
    final temporary = File('${marker.path}.tmp');
    final previous = File('${marker.path}.previous');
    await rejectSymlinkedPath(temporary.path);
    await rejectSymlinkedPath(previous.path);
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
      await _validateSafetyBackupPath(safetyBackupPath);
      final diagnostic = _readDiagnostic(data);
      _incident = RestoreRecoveryIncident(
        operationId: operationId,
        safetyBackupPath: safetyBackupPath,
        reason: reason,
        retryCurrentState: retryCurrentState as bool? ?? false,
        diagnostic: diagnostic,
      );
      _diagnostic = diagnostic;
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
    RestoreRecoveryDiagnostic? diagnostic,
  }) => _persistIncident(
    RestoreRecoveryIncident(
      operationId: operationId,
      safetyBackupPath: safetyBackup.path,
      reason: reason,
      retryCurrentState: retryCurrentState,
      diagnostic: diagnostic?.sanitized,
    ),
  );

  Future<void> markUnknownRequired({
    required String operationId,
    required String reason,
    RestoreRecoveryDiagnostic? diagnostic,
  }) => _persistIncident(
    RestoreRecoveryIncident(
      operationId: operationId.isEmpty ? 'unknown' : operationId,
      safetyBackupPath: '',
      reason: reason,
      retryCurrentState: false,
      diagnostic: diagnostic?.sanitized,
    ),
  );

  Future<void> _persistIncident(RestoreRecoveryIncident incident) async {
    final safeIncident = RestoreRecoveryIncident(
      operationId: incident.operationId,
      safetyBackupPath: incident.safetyBackupPath,
      reason: incident.reason,
      retryCurrentState: incident.retryCurrentState,
      diagnostic: incident.diagnostic?.sanitized,
    );
    await _validateSafetyBackupPath(safeIncident.safetyBackupPath);
    _incident = safeIncident;
    _diagnostic = safeIncident.diagnostic;
    notifyListeners();

    final marker = await _markerFile();
    await rejectSymlinkedPath(marker.path);
    await marker.parent.create(recursive: true);
    final temporary = File('${marker.path}.tmp');
    final previous = File('${marker.path}.previous');
    await rejectSymlinkedPath(temporary.path);
    await rejectSymlinkedPath(previous.path);

    await temporary.writeAsString(
      jsonEncode({
        'operationId': safeIncident.operationId,
        'safetyBackupPath': safeIncident.safetyBackupPath,
        'reason': safeIncident.reason,
        'retryCurrentState': safeIncident.retryCurrentState,
        if (safeIncident.diagnostic != null)
          'diagnosticStageCode': safeIncident.diagnostic!.stageCode,
        if (safeIncident.diagnostic != null)
          'diagnosticErrorCode': safeIncident.diagnostic!.errorCode,
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
    await rejectSymlinkedPath(marker.path);
    for (final file in <File>[
      marker,
      File('${marker.path}.tmp'),
      File('${marker.path}.previous'),
    ]) {
      await rejectSymlinkedPath(file.path);
      if (await file.exists()) await file.delete();
    }
    _incident = null;
    _diagnostic = null;
    notifyListeners();
  }

  void _setGenericIncident(String reason) {
    _incident = RestoreRecoveryIncident(
      operationId: 'unknown',
      safetyBackupPath: '',
      reason: reason,
      retryCurrentState: false,
    );
    _diagnostic = null;
    notifyListeners();
  }

  RestoreRecoveryDiagnostic? _readDiagnostic(Map<String, Object?> data) {
    final stageCode = data['diagnosticStageCode'];
    final errorCode = data['diagnosticErrorCode'];
    if (stageCode is! String || errorCode is! String) return null;
    final diagnostic = RestoreRecoveryDiagnostic(
      stageCode: stageCode,
      errorCode: errorCode,
    ).sanitized;
    if (diagnostic.stageCode == 'unknown' && stageCode != 'unknown') {
      return null;
    }
    if (diagnostic.errorCode == 'unknown' && errorCode != 'unknown') {
      return null;
    }
    return diagnostic;
  }

  Future<File> _markerFile() async {
    final evidence = await localDataManager.evidenceDirectory();
    return File('${evidence.path}.restore-recovery-required.json');
  }

  Future<void> _validateSafetyBackupPath(String value) async {
    if (value.isEmpty) return;
    if (!path.isAbsolute(value)) throw const FormatException();
    final root = path.normalize(
      path.absolute((await localDataManager.safetyBackupDirectory()).path),
    );
    final candidate = path.normalize(path.absolute(value));
    if (candidate == root || !path.isWithin(root, candidate)) {
      throw const FormatException();
    }
    if (await FileSystemEntity.type(root, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException();
    }
    var current = root;
    final relative = path.relative(candidate, from: root);
    for (final component in path.split(relative)) {
      if (component.isEmpty || component == '.') continue;
      current = path.join(current, component);
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException();
      }
    }
  }
}
