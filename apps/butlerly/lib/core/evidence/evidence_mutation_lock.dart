import 'dart:async';
import 'dart:collection';

/// Serializes mutations of Butlerly's local evidence filesystem.
///
/// Restore temporarily stages and may replace the evidence root, while normal
/// capture/removal operations add or delete immutable evidence files. Backup
/// also establishes its database/evidence snapshot under this boundary so both
/// sides refer to one logical state.
///
/// An uncontended operation starts synchronously. This is important for backup:
/// calling createBackup establishes the SQLite read transaction immediately,
/// rather than moving its snapshot boundary to a later microtask. Contended
/// operations are queued FIFO and begin only after their predecessor completes.
final class EvidenceMutationLock {
  EvidenceMutationLock._();

  static final Queue<void Function()> _queue = Queue<void Function()>();
  static bool _locked = false;

  static Future<T> runExclusive<T>(Future<T> Function() action) {
    if (!_locked) {
      _locked = true;
      return _execute(action);
    }

    final completer = Completer<T>();
    _queue.add(() {
      _execute(action).then(
        completer.complete,
        onError: completer.completeError,
      );
    });
    return completer.future;
  }

  static Future<T> _execute<T>(Future<T> Function() action) async {
    try {
      return await action();
    } finally {
      if (_queue.isEmpty) {
        _locked = false;
      } else {
        final next = _queue.removeFirst();
        next();
      }
    }
  }
}
