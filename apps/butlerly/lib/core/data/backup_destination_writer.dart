import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart' show sha256FileRange;
import 'package:path/path.dart' as path;

typedef BackupFileCopy =
    Future<File> Function(File source, String destinationPath);

/// Publishes a fully validated backup into a user-selected destination.
///
/// The source and rollback copy remain in Butlerly-owned storage. The writer
/// never creates a candidate, previous, or recovery file beside the selected
/// destination, which is important for sandboxed macOS save-panel paths.
abstract interface class BackupDestinationWriter {
  Future<void> publish({
    required File source,
    required File destination,
    required Directory privateDirectory,
    required String operationId,
  });
}

final class SandboxedBackupDestinationWriter
    implements BackupDestinationWriter {
  const SandboxedBackupDestinationWriter({BackupFileCopy? copy})
    : _copy = copy ?? _copyFile;

  final BackupFileCopy _copy;

  @override
  Future<void> publish({
    required File source,
    required File destination,
    required Directory privateDirectory,
    required String operationId,
  }) async {
    final hadExistingDestination = await destination.exists();
    final previous = File(
      path.join(
        privateDirectory.path,
        '.portable-backup-previous-$operationId.butlerlybackup',
      ),
    );
    var preservePrevious = false;

    if (hadExistingDestination) {
      await _copy(destination, previous.path);
      await _assertSameFile(destination, previous);
    }

    try {
      await _copy(source, destination.path);
      await _assertSameFile(source, destination);
    } catch (error, stack) {
      try {
        if (hadExistingDestination) {
          await _copy(previous, destination.path);
          await _assertSameFile(previous, destination);
        } else if (await destination.exists()) {
          await destination.delete();
        }
      } catch (rollbackError, rollbackStack) {
        preservePrevious = true;
        Error.throwWithStackTrace(
          BackupDestinationWriteException(
            error: error,
            rollbackError: rollbackError,
          ),
          rollbackStack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      try {
        if (!preservePrevious && await previous.exists()) {
          await previous.delete();
        }
      } catch (_) {}
    }
  }

  static Future<File> _copyFile(File source, String destinationPath) async {
    final output = File(destinationPath).openWrite();
    try {
      await output.addStream(source.openRead());
      await output.flush();
    } finally {
      await output.close();
    }
    return File(destinationPath);
  }

  static Future<void> _assertSameFile(File expected, File actual) async {
    if (!await actual.exists() ||
        await expected.length() != await actual.length() ||
        await sha256FileRange(expected) != await sha256FileRange(actual)) {
      throw StateError('Published backup does not match its source.');
    }
  }
}

final class BackupDestinationWriteException implements Exception {
  const BackupDestinationWriteException({
    required this.error,
    required this.rollbackError,
  });

  final Object error;
  final Object rollbackError;

  @override
  String toString() =>
      'Backup publication failed and rollback also failed: '
      '$error; rollback: $rollbackError';
}
