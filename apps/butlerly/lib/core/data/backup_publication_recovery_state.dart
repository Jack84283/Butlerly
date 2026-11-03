import 'package:butlerly/core/data/backup_destination_writer.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Process-visible state for a portable backup publication that needs the
/// user to re-authorize its external destination.
final class BackupPublicationRecoveryState extends ChangeNotifier {
  BackupPublicationRecoveryRequiredException? _incident;

  BackupPublicationRecoveryRequiredException? get incident => _incident;
  bool get isRecoveryRequired => _incident != null;

  /// Returns only the original destination basename for the native save
  /// picker. The recovery screen must suggest the recorded name so a user can
  /// re-authorize the exact destination; the private or parent path is never
  /// exposed to presentation or logs.
  String? get suggestedDestinationFileName {
    for (final recovery in _incident?.recoveries ?? const []) {
      final name = path.basename(recovery.destinationPath);
      if (name.isNotEmpty && name != '.' && name != '..') return name;
    }
    return null;
  }

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
