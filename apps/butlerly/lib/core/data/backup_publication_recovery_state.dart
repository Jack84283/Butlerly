import 'package:butlerly/core/data/backup_destination_writer.dart';
import 'package:flutter/foundation.dart';

/// Process-visible state for a portable backup publication that needs the
/// user to re-authorize its external destination.
final class BackupPublicationRecoveryState extends ChangeNotifier {
  BackupPublicationRecoveryRequiredException? _incident;

  BackupPublicationRecoveryRequiredException? get incident => _incident;
  bool get isRecoveryRequired => _incident != null;

  void markRequired(BackupPublicationRecoveryRequiredException incident) {
    _incident = incident;
    notifyListeners();
  }

  void clear() {
    if (_incident == null) return;
    _incident = null;
    notifyListeners();
  }
}
