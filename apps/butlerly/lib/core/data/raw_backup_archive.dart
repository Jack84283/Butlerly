import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly_database/butlerly_database.dart'
    show int64Bytes, int64FromBytes, sha256Bytes, sha256FileRange;
import 'package:path/path.dart' as path;

/// Container for a complete SQLite snapshot and the original evidence files.
///
/// No business rules, foreign keys, categories, budgets, or analysis findings
/// are interpreted. Their original bytes remain in the SQLite database.
/// Encryption is applied to this entire container by the backup service.
final class RawBackupArchive {
  const RawBackupArchive();

  static final _magic = ascii.encode('BUTLERLYRAW1');
  static const _format = 'butlerly-raw-backup';
  static const _formatVersion = 1;
  static const _maximumManifestBytes = 16 * 1024 * 1024;
  static final _shaPattern = RegExp(r'^[a-f0-9]{64}$');

  /// Writes a self-describing, streaming archive without modifying source
  /// database rows or source evidence files.
  Future<RawBackupInspection> write({
    required File sqliteSnapshot,
    required Directory evidenceDirectory,
    required Iterable<String> referencedEvidencePaths,
    required File destination,
    DateTime? createdAtUtc,
  }) async {
    await rejectEvidenceRoot(evidenceDirectory);
    if (!await sqliteSnapshot.exists()) {
      throw const FileSystemException('SQLite snapshot is unavailable.');
    }

    final files = <_RawFile>[];
    final names = <String>{};
    if (await evidenceDirectory.exists()) {
      await for (final entity in evidenceDirectory.list(
        recursive: true,
        followLinks: false,
      )) {
        await rejectEvidenceLink(entity);
        if (entity is! File) continue;
        final relative = await validateEvidencePath(
          evidenceDirectory,
          path.relative(entity.path, from: evidenceDirectory.path),
        );
        if (!names.add(evidencePathKey(relative))) {
          throw const FormatException(
            'Evidence filenames are not portable to this device.',
          );
        }
        files.add(_RawFile(
          relative,
          entity,
          await entity.length(),
          await sha256FileRange(entity),
        ));
      }
    }
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));

    // Missing optional content is reported, not recovered or used as a gate.
    final unavailable = <String>{};
    var unsafeReferenceCount = 0;
    for (final reference in referencedEvidencePaths) {
      if (reference.trim().isEmpty) continue;
      try {
        final relative = normalizeEvidencePath(reference);
        if (!names.contains(evidencePathKey(relative))) {
          unavailable.add(relative);
        }
      } on FormatException {
        unsafeReferenceCount++;
      }
    }

    final sqliteLength = await sqliteSnapshot.length();
    final sqliteHash = await sha256FileRange(sqliteSnapshot);
    final manifest = <String, Object?>{
      'format': _format,
      'formatVersion': _formatVersion,
      'createdAtUtc': (createdAtUtc ?? DateTime.now()).toUtc().toIso8601String(),
      'sqliteLength': sqliteLength,
      'sqliteSha256': sqliteHash,
      'attachments': [
        for (final file in files)
          {
            'path': file.relativePath,
            'length': file.length,
            'sha256': file.sha256,
          },
      ],
      'missingAttachmentPaths': unavailable.toList()..sort(),
      'unsafeReferenceCount': unsafeReferenceCount,
    };
    final metadata = utf8.encode(jsonEncode(manifest));
    if (metadata.length > _maximumManifestBytes) {
      throw const FormatException('Backup manifest is too large.');
    }
    final temporary = File(
      '${destination.path}.writing-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.parent.create(recursive: true);
    try {
      final sink = temporary.openWrite();
      try {
        sink.add(_magic);
        sink.add(int64Bytes(metadata.length));
        sink.add(ascii.encode(sha256Bytes(metadata)));
        sink.add(metadata);
        await sink.addStream(sqliteSnapshot.openRead());
        if (await sqliteSnapshot.length() != sqliteLength ||
            await sha256FileRange(sqliteSnapshot) != sqliteHash) {
          throw StateError('SQLite snapshot changed during packaging.');
        }
        for (final file in files) {
          await sink.addStream(file.source!.openRead());
          if (await file.source!.length() != file.length ||
              await sha256FileRange(file.source!) != file.sha256) {
            throw StateError('An attachment changed during packaging.');
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      final checked = await inspect(temporary);
      if (await destination.exists()) {
        throw const FileSystemException('Backup destination already exists.');
      }
      await temporary.rename(destination.path);
      return checked;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  /// Verifies byte lengths and hashes; does not validate business relationships.
  Future<RawBackupInspection> inspect(File archive) async {
    final parsed = await _readManifest(archive);
    var offset = parsed.payloadOffset;
    if (await sha256FileRange(
          archive,
          start: offset,
          endExclusive: offset + parsed.sqliteLength,
        ) != parsed.sqliteHash) {
      throw const FormatException('Backup SQLite bytes are not intact.');
    }
    offset += parsed.sqliteLength;
    for (final file in parsed.files) {
      if (await sha256FileRange(
            archive,
            start: offset,
            endExclusive: offset + file.length,
          ) != file.sha256) {
        throw const FormatException('Backup attachment bytes are not intact.');
      }
      offset += file.length;
    }
    if (offset != await archive.length()) {
      throw const FormatException('Backup contains unexpected trailing data.');
    }
    return RawBackupInspection(
      createdAtUtc: parsed.createdAtUtc,
      sqliteBytes: parsed.sqliteLength,
      attachmentCount: parsed.files.length,
      missingAttachmentCount:
          parsed.missingAttachmentPaths.length + parsed.unsafeReferenceCount,
    );
  }

  /// Extracts into a new private staging directory, never into live app data.
  /// The caller separately decides whether a verified staged database should
  /// be activated and how to recover from an interrupted activation.
  Future<RawBackupInspection> extract({
    required File archive,
    required Directory stagingDirectory,
  }) async {
    final inspection = await inspect(archive);
    if (await stagingDirectory.exists()) {
      throw const FileSystemException('Restore staging directory exists.');
    }
    await rejectSymlinkedPath(stagingDirectory.path);
    final parsed = await _readManifest(archive);
    await stagingDirectory.create(recursive: true);
    try {
      final sqlite = File(path.join(stagingDirectory.path, 'butlerly.db'));
      var offset = parsed.payloadOffset;
      await _copyRange(
        archive,
        sqlite,
        offset,
        parsed.sqliteLength,
        parsed.sqliteHash,
      );
      offset += parsed.sqliteLength;
      final root = Directory(path.join(stagingDirectory.path, 'evidence'));
      await root.create();
      for (final file in parsed.files) {
        final safe = await validateEvidencePath(root, file.relativePath);
        final destination = File(path.join(root.path, safe));
        await _copyRange(
          archive,
          destination,
          offset,
          file.length,
          file.sha256,
        );
        offset += file.length;
      }
      return inspection;
    } catch (_) {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> _copyRange(
    File source,
    File destination,
    int start,
    int length,
    String expectedHash,
  ) async {
    await destination.parent.create(recursive: true);
    final sink = destination.openWrite();
    try {
      await sink.addStream(source.openRead(start, start + length));
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (await destination.length() != length ||
        await sha256FileRange(destination) != expectedHash) {
      throw const FormatException('Extracted file integrity check failed.');
    }
  }

  Future<_RawManifest> _readManifest(File archive) async {
    final input = await archive.open(mode: FileMode.read);
    try {
      final magic = await input.read(_magic.length);
      if (!_sameBytes(magic, _magic)) {
        throw const FormatException('Unsupported Butlerly backup format.');
      }
      final lengthBytes = await input.read(8);
      final metadataLength = int64FromBytes(lengthBytes);
      if (metadataLength < 1 || metadataLength > _maximumManifestBytes) {
        throw const FormatException('Invalid Butlerly backup manifest length.');
      }
      final expectedHashBytes = await input.read(64);
      final metadata = await input.read(metadataLength);
      if (metadata.length != metadataLength ||
          ascii.decode(expectedHashBytes) != sha256Bytes(metadata)) {
        throw const FormatException('Backup manifest checksum mismatch.');
      }
      final decoded = jsonDecode(utf8.decode(metadata));
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != _format ||
          decoded['formatVersion'] != _formatVersion) {
        throw const FormatException('Unsupported Butlerly backup format.');
      }
      final sqliteLength = decoded['sqliteLength'];
      final sqliteHash = decoded['sqliteSha256'];
      final date = decoded['createdAtUtc'];
      final rawFiles = decoded['attachments'];
      final rawMissing = decoded['missingAttachmentPaths'];
      final unsafeCount = decoded['unsafeReferenceCount'];
      if (sqliteLength is! int ||
          sqliteLength < 1 ||
          sqliteHash is! String ||
          !_shaPattern.hasMatch(sqliteHash) ||
          date is! String ||
          rawFiles is! List ||
          rawMissing is! List ||
          unsafeCount is! int ||
          unsafeCount < 0) {
        throw const FormatException('Invalid Butlerly backup manifest.');
      }
      final files = <_RawFile>[];
      final names = <String>{};
      for (final value in rawFiles) {
        if (value is! Map<String, dynamic> ||
            value['path'] is! String ||
            value['length'] is! int ||
            value['sha256'] is! String) {
          throw const FormatException('Invalid backup attachment entry.');
        }
        final relative = normalizeEvidencePath(value['path'] as String);
        final length = value['length'] as int;
        final hash = value['sha256'] as String;
        if (length < 0 ||
            !_shaPattern.hasMatch(hash) ||
            !names.add(evidencePathKey(relative))) {
          throw const FormatException('Invalid or duplicate backup attachment.');
        }
        files.add(_RawFile(relative, null, length, hash));
      }
      final missing = <String>[];
      for (final value in rawMissing) {
        if (value is! String) {
          throw const FormatException('Invalid missing attachment entry.');
        }
        missing.add(normalizeEvidencePath(value));
      }
      final createdAt = DateTime.tryParse(date)?.toUtc();
      if (createdAt == null) {
        throw const FormatException('Invalid backup date.');
      }
      final payloadOffset = _magic.length + 8 + 64 + metadataLength;
      final expectedTotal = payloadOffset +
          sqliteLength +
          files.fold<int>(0, (total, file) => total + file.length);
      if (expectedTotal != await archive.length()) {
        throw const FormatException('Backup content length mismatch.');
      }
      return _RawManifest(
        createdAt,
        sqliteLength,
        sqliteHash,
        files,
        missing,
        unsafeCount,
        payloadOffset,
      );
    } finally {
      await input.close();
    }
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

final class RawBackupInspection {
  const RawBackupInspection({
    required this.createdAtUtc,
    required this.sqliteBytes,
    required this.attachmentCount,
    required this.missingAttachmentCount,
  });

  final DateTime createdAtUtc;
  final int sqliteBytes;
  final int attachmentCount;
  final int missingAttachmentCount;
  bool get hasWarnings => missingAttachmentCount > 0;
}

final class _RawFile {
  const _RawFile(this.relativePath, this.source, this.length, this.sha256);
  final String relativePath;
  final File? source;
  final int length;
  final String sha256;
}

final class _RawManifest {
  const _RawManifest(
    this.createdAtUtc,
    this.sqliteLength,
    this.sqliteHash,
    this.files,
    this.missingAttachmentPaths,
    this.unsafeReferenceCount,
    this.payloadOffset,
  );
  final DateTime createdAtUtc;
  final int sqliteLength;
  final String sqliteHash;
  final List<_RawFile> files;
  final List<String> missingAttachmentPaths;
  final int unsafeReferenceCount;
  final int payloadOffset;
}
