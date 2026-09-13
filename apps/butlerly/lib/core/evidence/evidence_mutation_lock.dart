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
/// operations are queued FIFO. A queued action starts only after the prior
/// caller's Future has been completed, so completion observers see the same
/// serialization order as the underlying filesystem mutations.
final class EvidenceMutationLock {
  EvidenceMutationLock._();

  static final Queue<void Function()> _queue = Queue<void Function()>();
  static bool _locked = false;

  static Future<T> runExclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    void start() => _start(action, completer);

    if (!_locked) {
      _locked = true;
      start();
    } else {
      _queue.add(start);
    }
    return completer.future;
  }

  static Future<void> _start<T>(
    Future<T> Function() action,
    Completer<T> completer,
  ) async {
    try {
      final result = await action();
      completer.complete(result);
    } catch (error, stack) {
      completer.completeError(error, stack);
    } finally {
      // complete()/completeError() schedules listeners before this microtask,
      // so the current caller's completion observers run before the next queued
      // mutation is allowed to begin.
      scheduleMicrotask(_releaseNext);
    }
  }

  static void _releaseNext() {
    if (_queue.isEmpty) {
      _locked = false;
      return;
    }
    final next = _queue.removeFirst();
    next();
  }
}
