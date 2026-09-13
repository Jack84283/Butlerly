import 'dart:async';

/// Serializes mutations of Butlerly's local evidence filesystem.
///
/// Restore temporarily stages and may replace the evidence root, while normal
/// capture/removal operations add or delete immutable evidence files. Both must
/// share one process-wide boundary so a file cannot appear or disappear between
/// restore staging and activation.
final class EvidenceMutationLock {
  EvidenceMutationLock._();

  static Future<void> _tail = Future<void>.value();

  static Future<T> runExclusive<T>(Future<T> Function() action) {
    final predecessor = _tail;
    final release = Completer<void>();
    _tail = release.future;

    return predecessor.then((_) => action()).whenComplete(() {
      if (!release.isCompleted) release.complete();
    });
  }
}
