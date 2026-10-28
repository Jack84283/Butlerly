import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly_database/butlerly_database.dart' show sha256FileRange;
import 'package:path/path.dart' as path;

typedef BackupFileCopy =
    Future<File> Function(File source, String destinationPath);

Future<String> _validatePrivateRecoveryPath(
  Directory privateDirectory,
  String value,
) async {
  if (!path.isAbsolute(value)) throw const FormatException();
  final root = path.normalize(path.absolute(privateDirectory.path));
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
  return candidate;
}

Future<void> _validateDestinationPath(File destination) async {
  final candidate = path.normalize(path.absolute(destination.path));
  final components = path.split(candidate);
  var current = components.first;
  for (var index = 1; index < components.length; index++) {
    current = path.join(current, components[index]);
    if (await FileSystemEntity.type(current, followLinks: false) ==
            FileSystemEntityType.link &&
        !_allowedSystemAlias(current)) {
      throw const FormatException(
        'Portable backup destination cannot contain a symbolic link.',
      );
    }
  }
}

bool _allowedSystemAlias(String value) =>
    Platform.isMacOS && (value == '/var' || value == '/tmp');

String _stagingPath(String destinationPath, String operationId) => path.join(
  path.dirname(path.normalize(path.absolute(destinationPath))),
  '.butlerly-backup-stage-$operationId.tmp',
);

Future<bool> _sameFileIdentity(File first, File second) async {
  if (!await first.exists() || !await second.exists()) return false;
  final left = await first.stat();
  final right = await second.stat();
  return left.type == FileSystemEntityType.file &&
      right.type == FileSystemEntityType.file &&
      left.mode == right.mode &&
      left.size == right.size &&
      left.modified == right.modified &&
      left.accessed == right.accessed &&
      left.changed == right.changed;
}

Future<bool> _sameFileContents(File expected, File actual) async {
  return await actual.exists() &&
      await expected.length() == await actual.length() &&
      await sha256FileRange(expected) == await sha256FileRange(actual);
}

Future<void> _validateDestinationIsolation({
  required File destination,
  required Directory privateDirectory,
  required File source,
  required File previous,
  required File staging,
}) async {
  final privateRoot = path.normalize(path.absolute(privateDirectory.path));
  final destinationPath = path.normalize(path.absolute(destination.path));
  final stagingPath = path.normalize(path.absolute(staging.path));
  final sourcePath = path.normalize(path.absolute(source.path));
  final previousPath = path.normalize(path.absolute(previous.path));
  if (destinationPath == privateRoot ||
      path.isWithin(privateRoot, destinationPath) ||
      stagingPath == privateRoot ||
      path.isWithin(privateRoot, stagingPath)) {
    throw const FormatException(
      'Portable backup destination must not use Butlerly private storage.',
    );
  }
  if (destinationPath == sourcePath ||
      destinationPath == previousPath ||
      stagingPath == sourcePath ||
      stagingPath == previousPath) {
    throw const FormatException(
      'Portable backup destination aliases a private artifact.',
    );
  }
  if (await destination.exists() &&
      (await _sameFileIdentity(source, destination) ||
          await _sameFileIdentity(previous, destination))) {
    throw const FormatException(
      'Portable backup destination aliases a private artifact.',
    );
  }
}

Future<void> _validateRecoveryArtifacts(
  Directory privateDirectory,
  BackupPublicationRecovery recovery,
  File source,
  File previous,
) async {
  final privateRoot = path.normalize(path.absolute(privateDirectory.path));
  final expectedSource = path.normalize(
    path.join(
      privateRoot,
      '.portable-backup-encrypted-${recovery.operationId}.butlerlybackup',
    ),
  );
  final expectedPrevious = path.normalize(
    path.join(
      privateRoot,
      '.portable-backup-previous-${recovery.operationId}.butlerlybackup',
    ),
  );
  if (path.normalize(path.absolute(source.path)) != expectedSource ||
      path.normalize(path.absolute(previous.path)) != expectedPrevious) {
    throw const FormatException(
      'Portable backup recovery artifact path changed.',
    );
  }
  if (recovery.sourceLength == null || recovery.sourceSha256 == null) {
    throw const FormatException(
      'Portable backup recovery metadata has no source fingerprint.',
    );
  }
  if (!await source.exists() ||
      await source.length() != recovery.sourceLength ||
      await sha256FileRange(source) != recovery.sourceSha256) {
    throw StateError('Portable backup recovery source was changed.');
  }
  if (await previous.exists()) {
    if (recovery.previousLength == null || recovery.previousSha256 == null) {
      throw const FormatException(
        'Portable backup recovery metadata has no previous fingerprint.',
      );
    }
    if (await previous.length() != recovery.previousLength ||
        await sha256FileRange(previous) != recovery.previousSha256) {
      throw StateError('Portable backup recovery copy was changed.');
    }
    if (await _sameFileIdentity(source, previous)) {
      throw const FormatException(
        'Portable backup recovery artifacts alias one another.',
      );
    }
  } else if (recovery.previousReady) {
    throw StateError('Portable backup recovery copy is missing.');
  }
}

Future<void> _atomicCopy({
  required BackupFileCopy copy,
  required File source,
  required File destination,
  required File staging,
  required bool replaceExistingStaging,
}) async {
  await _validateDestinationPath(staging);
  if (await staging.exists()) {
    if (!replaceExistingStaging) {
      throw StateError('Portable backup staging file already exists.');
    }
    await staging.delete();
  }
  await copy(source, staging.path);
  if (!await _sameFileContents(source, staging)) {
    throw StateError('Portable backup staging copy does not match its source.');
  }
  await staging.rename(destination.path);
  if (!await _sameFileContents(source, destination)) {
    throw StateError('Published backup does not match its source.');
  }
}

final class BackupPublicationRecovery {
  const BackupPublicationRecovery({
    required this.operationId,
    required this.sourcePath,
    required this.destinationPath,
    required this.previousPath,
    required this.hadExistingDestination,
    required this.previousReady,
    this.sourceLength,
    this.sourceSha256,
    this.previousLength,
    this.previousSha256,
  });

  factory BackupPublicationRecovery.fromJson(Map<String, Object?> data) {
    final operationId = data['operationId'];
    final sourcePath = data['sourcePath'];
    final destinationPath = data['destinationPath'];
    final previousPath = data['previousPath'];
    final hadExistingDestination = data['hadExistingDestination'];
    final previousReady = data['previousReady'];
    final sourceLength = data['sourceLength'];
    final sourceSha256 = data['sourceSha256'];
    final previousLength = data['previousLength'];
    final previousSha256 = data['previousSha256'];
    if (operationId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(operationId) ||
        sourcePath is! String ||
        !path.isAbsolute(sourcePath) ||
        destinationPath is! String ||
        !path.isAbsolute(destinationPath) ||
        previousPath is! String ||
        !path.isAbsolute(previousPath) ||
        hadExistingDestination is! bool ||
        previousReady is! bool ||
        (sourceLength != null && sourceLength is! int) ||
        (sourceLength is int && sourceLength < 0) ||
        (sourceSha256 != null &&
            (sourceSha256 is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceSha256))) ||
        (previousLength != null && previousLength is! int) ||
        (previousLength is int && previousLength < 0) ||
        (previousSha256 != null &&
            (previousSha256 is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(previousSha256)))) {
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
      sourceLength: sourceLength as int?,
      sourceSha256: sourceSha256 as String?,
      previousLength: previousLength as int?,
      previousSha256: previousSha256 as String?,
    );
  }

  final String operationId;
  final String sourcePath;
  final String destinationPath;
  final String previousPath;
  final bool hadExistingDestination;
  final bool previousReady;
  final int? sourceLength;
  final String? sourceSha256;
  final int? previousLength;
  final String? previousSha256;

  BackupPublicationRecovery copyWith({
    bool? previousReady,
    String? sourcePath,
    String? previousPath,
    int? sourceLength,
    String? sourceSha256,
    int? previousLength,
    String? previousSha256,
  }) => BackupPublicationRecovery(
    operationId: operationId,
    sourcePath: sourcePath ?? this.sourcePath,
    destinationPath: destinationPath,
    previousPath: previousPath ?? this.previousPath,
    hadExistingDestination: hadExistingDestination,
    previousReady: previousReady ?? this.previousReady,
    sourceLength: sourceLength ?? this.sourceLength,
    sourceSha256: sourceSha256 ?? this.sourceSha256,
    previousLength: previousLength ?? this.previousLength,
    previousSha256: previousSha256 ?? this.previousSha256,
  );

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'sourcePath': sourcePath,
    'destinationPath': destinationPath,
    'previousPath': previousPath,
    'hadExistingDestination': hadExistingDestination,
    'previousReady': previousReady,
    if (sourceLength != null) 'sourceLength': sourceLength,
    if (sourceSha256 != null) 'sourceSha256': sourceSha256,
    if (previousLength != null) 'previousLength': previousLength,
    if (previousSha256 != null) 'previousSha256': previousSha256,
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
    await rejectSymlinkedPath(privateDirectory.path);
    await privateDirectory.create(recursive: true);
    final persisted = await _withFingerprints(recovery);
    final marker = markerFile(privateDirectory, recovery.operationId);
    final temporary = File('${marker.path}.tmp');
    await rejectSymlinkedPath(marker.path);
    await rejectSymlinkedPath(temporary.path);
    await temporary.writeAsString(jsonEncode(persisted.toJson()), flush: true);
    if (await marker.exists()) await marker.delete();
    await temporary.rename(marker.path);
  }

  Future<BackupPublicationRecovery> _withFingerprints(
    BackupPublicationRecovery recovery,
  ) async {
    var result = recovery;
    final source = File(recovery.sourcePath);
    if ((result.sourceLength == null || result.sourceSha256 == null) &&
        await source.exists()) {
      result = result.copyWith(
        sourceLength: await source.length(),
        sourceSha256: await sha256FileRange(source),
      );
    }
    final previous = File(recovery.previousPath);
    if ((result.previousLength == null || result.previousSha256 == null) &&
        await previous.exists()) {
      result = result.copyWith(
        previousLength: await previous.length(),
        previousSha256: await sha256FileRange(previous),
      );
    }
    return result;
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
    await rejectSymlinkedPath(privateDirectory.path);
    for (final file in <File>[
      markerFile(privateDirectory, recovery.operationId),
      File('${markerFile(privateDirectory, recovery.operationId).path}.tmp'),
    ]) {
      await rejectSymlinkedPath(file.path);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<List<BackupPublicationRecovery>> read(
    Directory privateDirectory,
  ) async {
    await rejectSymlinkedPath(privateDirectory.path);
    if (!await privateDirectory.exists()) return const [];
    final markers = <String, File>{};
    await for (final entity in privateDirectory.list(followLinks: false)) {
      final name = path.basename(entity.path);
      if (!name.startsWith('.portable-backup-recovery-') ||
          (!name.endsWith('.json') && !name.endsWith('.json.tmp'))) {
        continue;
      }
      if (entity is Link) {
        throw BackupPublicationRecoveryRequiredException(
          'Portable backup recovery metadata is a symbolic link: ${entity.path}',
        );
      }
      if (entity is! File) {
        throw BackupPublicationRecoveryRequiredException(
          'Portable backup recovery metadata is not a file: ${entity.path}',
        );
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
        final recovery = BackupPublicationRecovery.fromJson(
          decoded.cast<String, Object?>(),
        );
        final normalized = recovery.copyWith(
          sourcePath: await _validatePrivateRecoveryPath(
            privateDirectory,
            recovery.sourcePath,
          ),
          previousPath: await _validatePrivateRecoveryPath(
            privateDirectory,
            recovery.previousPath,
          ),
        );
        // Markers written before artifact fingerprints were introduced are
        // still recoverable because their private artifact names were already
        // deterministic. Hydrate and rewrite them before the recovery manager
        // applies the stricter integrity checks, so an upgrade cannot strand a
        // valid interrupted publication behind a permanent recovery overlay.
        final sourceExists = await File(normalized.sourcePath).exists();
        final previousExists = await File(normalized.previousPath).exists();
        final needsMigration =
            sourceExists &&
                (normalized.sourceLength == null ||
                    normalized.sourceSha256 == null) ||
            previousExists &&
                (normalized.previousLength == null ||
                    normalized.previousSha256 == null);
        final migrated = await _withFingerprints(normalized);
        if (needsMigration) {
          await write(privateDirectory, migrated);
        }
        recoveries.add(migrated);
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
    for (final candidate in recoveries) {
      BackupPublicationRecovery recovery;
      try {
        recovery = candidate.copyWith(
          sourcePath: await _validatePrivateRecoveryPath(
            privateDirectory,
            candidate.sourcePath,
          ),
          previousPath: await _validatePrivateRecoveryPath(
            privateDirectory,
            candidate.previousPath,
          ),
        );
      } on Exception {
        unresolved.add(candidate);
        continue;
      }
      final destinationAuthorized =
          authorizedDestinationPath != null &&
          path.normalize(recovery.destinationPath) ==
              path.normalize(authorizedDestinationPath);
      if (authorizedDestinationPath != null && !destinationAuthorized) {
        unresolved.add(recovery);
        continue;
      }
      try {
        await _recoverOne(
          privateDirectory,
          recovery,
          allowDestinationReplacement: destinationAuthorized,
        );
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
    BackupPublicationRecovery recovery, {
    required bool allowDestinationReplacement,
  }) async {
    final source = File(recovery.sourcePath);
    final destination = File(recovery.destinationPath);
    final previous = File(recovery.previousPath);
    final staging = File(_stagingPath(destination.path, recovery.operationId));
    await _validateDestinationPath(destination);
    await _validateDestinationPath(staging);
    await _validateDestinationIsolation(
      destination: destination,
      privateDirectory: privateDirectory,
      source: source,
      previous: previous,
      staging: staging,
    );
    await _validateRecoveryArtifacts(
      privateDirectory,
      recovery,
      source,
      previous,
    );

    if (recovery.hadExistingDestination && !recovery.previousReady) {
      // The selected destination cannot be modified before previousReady is
      // persisted. The external destination therefore remains authoritative;
      // discard only the unneeded private operation artifacts.
      if (!await destination.exists()) {
        throw StateError(
          'Portable backup destination disappeared before its previous copy '
          'was secured.',
        );
      }
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
      if (!await source.exists()) {
        throw StateError(
          'Portable backup recovery source is missing; refusing to mutate '
          'the selected destination.',
        );
      }
      if (await destination.exists()) {
        if (await source.exists() && await _sameFile(source, destination)) {
          await _complete(privateDirectory, recovery, previous);
          return;
        }
        if (!allowDestinationReplacement) {
          throw StateError(
            'Portable backup destination changed after publication '
            'interruption.',
          );
        }
        await destination.delete();
      } else if (!allowDestinationReplacement) {
        throw StateError(
          'Portable backup destination requires explicit authorization '
          'before publication recovery.',
        );
      }
      await _atomicCopy(
        copy: _copy,
        source: source,
        destination: destination,
        staging: staging,
        replaceExistingStaging: true,
      );
      await _complete(privateDirectory, recovery, previous);
      return;
    }

    if (!await previous.exists()) {
      throw StateError('Portable backup recovery copy is missing.');
    }
    if (await destination.exists()) {
      if (await _sameFile(previous, destination) ||
          (await source.exists() && await _sameFile(source, destination))) {
        await _complete(privateDirectory, recovery, previous);
        return;
      }
      if (allowDestinationReplacement) {
        await _atomicCopy(
          copy: _copy,
          source: previous,
          destination: destination,
          staging: staging,
          replaceExistingStaging: true,
        );
        await _complete(privateDirectory, recovery, previous);
        return;
      }
      throw StateError(
        'Portable backup destination changed after publication interruption.',
      );
    }

    if (!allowDestinationReplacement) {
      throw StateError(
        'Portable backup destination requires explicit authorization before '
        'publication recovery.',
      );
    }
    await _atomicCopy(
      copy: _copy,
      source: previous,
      destination: destination,
      staging: staging,
      replaceExistingStaging: true,
    );
    await _complete(privateDirectory, recovery, previous);
  }

  Future<void> _complete(
    Directory privateDirectory,
    BackupPublicationRecovery recovery,
    File previous,
  ) async {
    final staging = File(
      _stagingPath(recovery.destinationPath, recovery.operationId),
    );
    await _validateDestinationPath(staging);
    if (await staging.exists()) await staging.delete();
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
    return _sameFileContents(expected, actual);
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
    await _validateDestinationPath(destination);
    final staging = File(_stagingPath(destination.path, operationId));
    await _validateDestinationPath(staging);
    final previous = File(
      path.join(
        privateDirectory.path,
        '.portable-backup-previous-$operationId.butlerlybackup',
      ),
    );
    await _validateDestinationIsolation(
      destination: destination,
      privateDirectory: privateDirectory,
      source: source,
      previous: previous,
      staging: staging,
    );
    if (await staging.exists()) {
      throw StateError('Portable backup staging file already exists.');
    }
    final hadExistingDestination = await destination.exists();
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
      await _atomicCopy(
        copy: _copy,
        source: source,
        destination: destination,
        staging: staging,
        replaceExistingStaging: false,
      );
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
          await _atomicCopy(
            copy: _copy,
            source: previous,
            destination: destination,
            staging: staging,
            replaceExistingStaging: true,
          );
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
        if (recoveryFinalized && await staging.exists()) {
          await staging.delete();
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
    if (!await _sameFileContents(expected, actual)) {
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
