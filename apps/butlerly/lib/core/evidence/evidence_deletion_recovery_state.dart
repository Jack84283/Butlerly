import 'package:flutter/foundation.dart';

/// Process-visible gate for staged evidence deletions that need another
/// integrity-checked recovery attempt before ordinary use can continue.
final class EvidenceDeletionRecoveryState extends ChangeNotifier {
  Object? _failure;

  Object? get failure => _failure;
  bool get isRecoveryRequired => _failure != null;

  void markRequired(Object failure) {
    _failure = failure;
    notifyListeners();
  }

  void clear() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }
}
