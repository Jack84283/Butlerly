import 'dart:io';

import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Checks peak private staging demand before copying/encrypting large files.
///
/// This is a conservative, best-effort preflight, never a substitute for
/// handling ENOSPC during writes (another process can consume space later).
/// The host implementations use the actual filesystem containing [directory].
final class StorageSpacePreflight {
  StorageSpacePreflight._();

  static const MethodChannel _channel = MethodChannel(
    'butlerly/storage_capacity',
  );
  static const int _headroom = 64 * 1024 * 1024;

  static Future<int?> freeBytes(Directory directory) async {
    if (kIsWeb) return null;
    try {
      final available = await _channel.invokeMethod<int>('availableBytes', {
        'path': directory.path,
      });
      if (available != null && available >= 0) return available;
    } on MissingPluginException {
      // Flutter unit tests and non-mobile hosts may not register a channel.
    } on PlatformException {
      // Platform security/permission failure: rely on ENOSPC write handling.
    }
    if (!Platform.isLinux) return null;
    try {
      final output = await Process.run('df', ['-Pk', directory.path]);
      if (output.exitCode != 0) return null;
      final lines = (output.stdout as String).trim().split('\n');
      if (lines.length < 2) return null;
      final values = lines.last.trim().split(RegExp(r'\s+'));
      if (values.length < 4) return null;
      final kilobytes = int.tryParse(values[3]);
      return kilobytes == null ? null : kilobytes * 1024;
    } catch (_) {
      return null;
    }
  }

  /// A filesystem identity, not a path prefix: different directories and
  /// symlink-free mount points can still share the same capacity pool.
  static Future<String?> filesystemId(Directory directory) async {
    if (kIsWeb) return null;
    try {
      final id = await _channel.invokeMethod<String>('filesystemId', {
        'path': directory.path,
      });
      if (id != null && id.isNotEmpty) return id;
    } on MissingPluginException {
      // Tests and older platform embedders may lack this API.
    } on PlatformException {
      // Fail conservative below rather than assuming separate volumes.
    }
    if (!Platform.isLinux) return null;
    try {
      final result = await Process.run('stat', [
        '-c',
        '%d',
        '--',
        directory.path,
      ]);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}
    return null;
  }

  /// Check both peak requirements against a shared free-space pool whenever
  /// directories use one filesystem. If identity cannot be established,
  /// conservatively assume they share capacity. Separate volumes are checked
  /// individually, avoiding an unnecessarily high requirement on either.
  static Future<void> requireBackupCapacity({
    required Directory privateDirectory,
    required Directory destinationDirectory,
    required int privateStagingBytes,
    required int destinationStagingBytes,
    Future<int?> Function(Directory)? probe,
    Future<String?> Function(Directory)? identityProbe,
  }) async {
    final identity = identityProbe ?? filesystemId;
    final internalId = await identity(privateDirectory);
    final externalId = await identity(destinationDirectory);
    final definitelyDifferent =
        internalId != null &&
        externalId != null &&
        internalId != externalId;

    await requireAvailable(
      privateDirectory,
      stagingBytes: privateStagingBytes +
          (definitelyDifferent ? 0 : destinationStagingBytes),
      probe: probe,
    );
    await requireAvailable(
      destinationDirectory,
      stagingBytes: destinationStagingBytes,
      probe: probe,
    );
  }

  /// Includes a fixed reserve so small untracked WAL/metadata writes remain
  /// possible. Null capacity means the platform cannot provide a trustworthy
  /// measurement; actual writes must still fail safely on insufficient space.
  static Future<void> requireAvailable(
    Directory directory, {
    required int stagingBytes,
    Future<int?> Function(Directory directory)? probe,
  }) async {
    if (stagingBytes < 0) throw ArgumentError.value(stagingBytes);
    final available = await (probe ?? freeBytes)(directory);
    final required = stagingBytes + _headroom;
    if (available != null && available < required) {
      throw FileSystemException(
        'Not enough free space to safely stage Backup/Restore. '
        'Required: $required bytes; available: $available bytes.',
        directory.path,
        const OSError('No space left on device', 28),
      );
    }
  }

  static Future<int> evidenceBytes(Directory directory) async {
    await rejectEvidenceTree(directory);
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      await rejectEvidenceLink(entry);
      if (entry is File) total += await entry.length();
    }
    return total;
  }

  /// Snapshot + archive + encrypted archive + verification/extraction.
  static int backupStagingBytes({
    required int databaseBytes,
    required int evidenceBytes,
  }) => databaseBytes * 4 + evidenceBytes * 3;

  /// Decryption, extraction, migration, copies of live and staged evidence.
  /// Merge's disposable local snapshot is included in this conservative cap.
  static int restoreStagingBytes({
    required int archiveBytes,
    required int databaseBytes,
    required int evidenceBytes,
  }) => archiveBytes * 4 + databaseBytes * 3 + evidenceBytes * 2;
}
