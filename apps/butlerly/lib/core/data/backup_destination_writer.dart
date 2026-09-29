import 'dart:convert';
import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart' show sha256FileRange;
import 'package:path/path.dart' as path;

typedef BackupFileCopy =
    Future<File> Function(File source, String destinationPath);

final class BackupPublicationRecovery {
  const BackupPublicationRecovery({
    required this.operationId,
    required this.sourcePath,
    required this.destinationPath,
    required this.previousPath,
    required this.hadExistingDestination,
    required this.previousReady,
  });

  factory BackupPublicationRecovery.fromJson(Map<String, Object?> data) {
    final operationId = data['operationId'];
    final sourcePath = data['sourcePath'];
    final destinationPath = data['destinationPath'];
    final previousPath = data['previousPath'];
    final hadExistingDestination = data['hadExistingDestination'];
    final previousReady = data['previousReady'];
    if (operationId is! String ||
        operationId.isEmpty ||
        sourcePath is! String ||
        sourcePath.isEmpty ||
        destinationPath is! String ||
        destinationPath.isEmpty ||
        previousPath is! String ||
        hadExistingDestination is! bool ||
        previousReady is! bool) {
      throw const FormatException(
        'Incomplete portable backup recovery metadata.',
      );
    }
    return BackupPublicationRecovery(
      operationId: operationId,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      previousPath: previousPath,
      hadExistingDestination: hadExistingDestination,
      previousReady: previousReady,
    );
  }

  final String operationId;
  final String sourcePath;
  final String destinationPath;
  final String previousPath;
  final bool hadExistingDestination;
  final bool previousReady;

  BackupPublicationRecovery copyWith({bool? previousReady}) =>
      BackupPublicationRecovery(
        operationId: operationId,
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        previousPath: previousPath,
        hadExistingDestination: hadExistingDestination,
        previousReady: previousReady ?? this.previousReady,
      );

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'sourcePath': sourcePath,
    'destinationPath': destinationPath,
    'previousPath': previousPath,
    'hadExistingDestination': hadExistingDestination,
    'previousReady': previousReady,
  };
}

abstract interface class BackupPublicationRecoveryStore {
  Future<void> write(
    Directory privateDirectory,
    BackupPublicationRecovery recovery,
  );

  Future<void> clear(
    Directory privateDirectory,
    BackupPublicationRecovery recovery,
  );

  Future<List<BackupPublicationRecovery>> read(Directory privateDirectory);
}

final class FileBackupPublicationRecoveryStore
    implements BackupPublicationRecoveryStore {
  const FileBackupPublicationRecoveryStore();

  @override
  Future<void> write(
    Directory privateDirectory,
    BackupPublicationRecovery recovery,
  ) async {
    await privateDirectory.create(recursive: true);
    final marker = markerFile(privateDirectory, recovery.operationId);
    final temporary = File('${marker.path}.tmp');
    await temporary.writeAsString(jsonEncode(recovery.toJson()), flush: true);
    if (await marker.exists()) await marker.delete();
    await temporary.rename(marker.path);
  }

  static String markerName(String operationId) =>
      '.portable-backup-recovery-$operationId.json';

  static File markerFile(Directory privateDirectory, String operationId) =>
      File(path.join(privateDirectory.path, markerName(operationId)));

  @override
  Future<void> clear(
    Directory privateDirectory,
    BackupPublicationRecovery recovery,
  ) async {
    for (final file in <File>[
      markerFile(privateDirectory, recovery.operationId),
      File('${markerFile(privateDirectory, recovery.operationId).path}.tmp'),
    ]) {
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<List<BackupPublicationRecovery>> read(
    Directory privateDirectory,
  ) async {
    if (!await privateDirectory.exists()) return const [];
    final markers = <String, File>{};
    await for (final entity in privateDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      if (!name.startsWith('.portable-backup-recovery-') ||
          (!name.endsWith('.json') && !name.endsWith('.json.tmp'))) {
        continue;
      }
      final key = name
          .substring('.portable-backup-recovery-'.length)
          .replaceFirst(RegExp(r'\.json(\.tmp)?$'), '');
      if (name.endsWith('.json.tmp')) {
        markers[key] = entity;
      } else {
        markers.putIfAbsent(key, () => entity);
      }
    }

    final recoveries = <BackupPublicationRecovery>[];
    for (final marker in markers.values) {
      try {
        final decoded = jsonDecode(await marker.readAsString());
        if (decoded is! Map) throw const FormatException();
        recoveries.add(
          BackupPublicationRecovery.fromJson(decoded.cast<String, Object?>()),
        );
      } on Exception catch (_, stack) {
        Error.throwWithStackTrace(
          BackupPublicationRecoveryRequiredException(
            'Portable backup recovery metadata is unreadable: ${marker.path}',
          ),
          stack,
        );
      }
    }
    return recoveries;
  }
}

final class BackupPublicationRecoveryManager {
  const BackupPublicationRecoveryManager({
    BackupPublicationRecoveryStore? store,
    BackupFileCopy? copy,
  }) : _store = store ?? const FileBackupPublicationRecoveryStore(),
       _copy = copy ?? _copyFile;

  final BackupPublicationRecoveryStore _store;
  final BackupFileCopy _copy;

  Future<void> recover(
    Directory privateDirectory, {
    String? authorizedDestinationPath,
  }) async {
    final recoveries = await _store.read(privateDirectory);
    final unresolved = <BackupPublicationRecovery>[];
    for (final recovery in recoveries) {
      if (authorizedDestinationPath != null &&
          path.normalize(recovery.destinationPath) !=
              path.normalize(authorizedDestinationPath)) {
        unresolved.add(recovery);
        continue;
      }
      try {
        await _recoverOne(privateDirectory, recovery);
      } catch (_) {
        unresolved.add(recovery);
      }
    }
    if (unresolved.isNotEmpty) {
      throw BackupPublicationRecoveryRequiredException(
        'Portable backup publication recovery requires access to: '
        '${unresolved.map((value) => value.destinationPath).join(', ')}',
        recoveries: unresolved,
      );
    }
  }

  Future<Set<String>> activeArtifactNames(Directory privateDirectory) async {
    final names = <String>{};
    if (!await privateDirectory.exists()) return names;
    await for (final entity in privateDirectory.list(followLinks: false)) {
      if (entity is File &&
          path.basename(entity.path).startsWith('.portable-backup-recovery-')) {
        names.add(path.basename(entity.path));
      }
    }
    try {
      final recoveries = await _store.read(privateDirectory);
      for (final recovery in recoveries) {
        names
          ..add(path.basename(recovery.sourcePath))
          ..add(path.basename(recovery.previousPath));
      }
    } on BackupPublicationRecoveryRequiredException {
      // Keep every portable artifact when metadata is unreadable. Deleting
      // anything would make an interrupted publication unrecoverable.
      return names..add('*');
    }
    return names;
  }

  Future<void> _recoverOne(
    Directory privateDirectory,
    BackupPublicationRecovery recovery,
  ) async {
    final source = File(recovery.sourcePath);
    final destination = File(recovery.destinationPath);
    final previous = File(recovery.previousPath);

    if (recovery.hadExistingDestination && !recovery.previousReady) {
      // The selected destination cannot be modified before previousReady is
      // persisted. The external destination therefore remains authoritative;
      // discard only the unneeded private operation artifacts.
      await _complete(privateDirectory, recovery, previous);
      return;
    }

    if (await source.exists() &&
        await destination.exists() &&
        await _sameFile(source, destination)) {
      await _complete(privateDirectory, recovery, previous);
      return;
    }

    if (!recovery.hadExistingDestination) {
      if (await destination.exists()) await destination.delete();
      await _complete(privateDirectory, recovery, previous);
      return;
    }

    if (!await previous.exists()) {
      throw StateError('Portable backup recovery copy is missing.');
    }
    if (await destination.exists() && await _sameFile(previous, destination)) {
      await _complete(privateDirectory, recovery, previous);
      return;
    }

    await _copy(previous, destination.path);
    if (!await _sameFile(previous, destination)) {
      throw StateError('Portable backup recovery copy could not be published.');
    }
    await _complete(privateDirectory, recovery, previous);
  }

  Future<void> _complete(
    Directory privateDirectory,
    BackupPublicationRecovery recovery,
    File previous,
  ) async {
    await _store.clear(privateDirectory, recovery);
    final source = File(recovery.sourcePath);
    if (source.path != recovery.destinationPath && await source.exists()) {
      await source.delete();
    }
    if (await previous.exists()) await previous.delete();
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

  static Future<bool> _sameFile(File expected, File actual) async {
    return await actual.exists() &&
        await expected.length() == await actual.length() &&
        await sha256FileRange(expected) == await sha256FileRange(actual);
  }
}

final class BackupPublicationRecoveryRequiredException implements Exception {
  const BackupPublicationRecoveryRequiredException(
    this.message, {
    this.recoveries = const [],
    this.cause,
  });

  final String message;
  final List<BackupPublicationRecovery> recoveries;
  final Object? cause;

  @override
  String toString() => message;
}

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
  const SandboxedBackupDestinationWriter({
    BackupFileCopy? copy,
    BackupPublicationRecoveryStore? recoveryStore,
  }) : _copy = copy ?? _copyFile,
       _recoveryStore =
           recoveryStore ?? const FileBackupPublicationRecoveryStore();

  final BackupFileCopy _copy;
  final BackupPublicationRecoveryStore _recoveryStore;

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
    var recoveryFinalized = false;
    var previousReady = false;
    final recovery = BackupPublicationRecovery(
      operationId: operationId,
      sourcePath: source.path,
      destinationPath: destination.path,
      previousPath: previous.path,
      hadExistingDestination: hadExistingDestination,
      previousReady: false,
    );
    await _recoveryStore.write(privateDirectory, recovery);

    try {
      if (hadExistingDestination) {
        await _copy(destination, previous.path);
        await _assertSameFile(destination, previous);
        await _recoveryStore.write(
          privateDirectory,
          recovery.copyWith(previousReady: true),
        );
        previousReady = true;
      }
      await _copy(source, destination.path);
      await _assertSameFile(source, destination);
      try {
        await _recoveryStore.clear(privateDirectory, recovery);
        recoveryFinalized = true;
      } catch (error, stack) {
        Error.throwWithStackTrace(
          BackupPublicationRecoveryRequiredException(
            'Portable backup publication completed but its recovery state '
            'could not be finalized.',
            recoveries: [recovery],
            cause: error,
          ),
          stack,
        );
      }
    } catch (error, stack) {
      if (error is BackupPublicationRecoveryRequiredException) {
        Error.throwWithStackTrace(error, stack);
      }
      try {
        if (hadExistingDestination && previousReady) {
          await _copy(previous, destination.path);
          await _assertSameFile(previous, destination);
        } else if (!hadExistingDestination && await destination.exists()) {
          await destination.delete();
        }
        try {
          await _recoveryStore.clear(privateDirectory, recovery);
          recoveryFinalized = true;
        } catch (clearError, clearStack) {
          Error.throwWithStackTrace(
            BackupPublicationRecoveryRequiredException(
              'Portable backup rollback completed but its recovery state '
              'could not be finalized.',
              recoveries: [recovery],
              cause: clearError,
            ),
            clearStack,
          );
        }
      } catch (rollbackError, rollbackStack) {
        if (rollbackError is BackupPublicationRecoveryRequiredException) {
          Error.throwWithStackTrace(rollbackError, rollbackStack);
        }
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
        if (recoveryFinalized && await previous.exists()) {
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
