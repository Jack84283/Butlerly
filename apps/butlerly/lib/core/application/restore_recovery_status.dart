import 'package:flutter/foundation.dart';

/// Privacy-safe restore failure metadata shown on the controlled recovery
/// surface.
///
/// Only bounded diagnostic codes are retained. This value must never contain
/// paths, SQL text, exception messages, financial data, or stack traces.
final class RestoreRecoveryDiagnostic {
  const RestoreRecoveryDiagnostic({
    required this.stageCode,
    required this.errorCode,
  });

  final String stageCode;
  final String errorCode;

  static const stageCodes = <String>{
    'restore_activation',
    'restore_validation',
    'unknown',
  };

  static const errorCodes = <String>{
    'backup_encryption_verification',
    'backup_password_policy',
    'backup_publication_recovery_required',
    'backup_storage',
    'database',
    'filesystem',
    'format',
    'invalid_argument',
    'restore_password_or_integrity',
    'restore_password_required',
    'restore_recovery_required',
    'state',
    'unknown',
  };

  RestoreRecoveryDiagnostic get sanitized => RestoreRecoveryDiagnostic(
    stageCode: stageCodes.contains(stageCode) ? stageCode : 'unknown',
    errorCode: errorCodes.contains(errorCode) ? errorCode : 'unknown',
  );
}

/// Application-facing recovery status used by the root shell and recovery UI.
///
/// The persistence-backed implementation remains in the data layer; feature
/// presentation depends only on this bounded application contract.
abstract interface class RestoreRecoveryStatus implements Listenable {
  bool get isRecoveryRequired;

  RestoreRecoveryDiagnostic? get diagnostic;
}
