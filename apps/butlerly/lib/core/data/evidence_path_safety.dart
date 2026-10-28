import 'dart:io';

import 'package:path/path.dart' as path;

/// Rejects symlinks in an absolute private path before Butlerly creates or
/// mutates any component. Missing trailing components are allowed so callers
/// can safely create a new private directory tree.
Future<void> rejectSymlinkedPath(
  String value, {
  String message = 'Unsafe private path.',
}) async {
  final candidate = path.normalize(path.absolute(value));
  final components = path.split(candidate);
  var current = components.first;
  for (var index = 1; index < components.length; index++) {
    current = path.join(current, components[index]);
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (type == FileSystemEntityType.link &&
        !isAllowedSystemPathAlias(current)) {
      throw FormatException(message);
    }
    if (type == FileSystemEntityType.notFound) break;
  }
}

/// Returns whether [value] is an operating-system alias used by Apple
/// sandbox paths rather than a user-controlled link inside Butlerly data.
///
/// Both macOS and iOS can expose application-container paths through the
/// `/var` and `/tmp` aliases. These aliases must not be treated as evidence
/// symlinks, while links below the application container remain rejected.
bool isAllowedSystemPathAlias(String value, {bool? isMacOS, bool? isIOS}) {
  final appleUnix = (isMacOS ?? Platform.isMacOS) || (isIOS ?? Platform.isIOS);
  return appleUnix && (value == '/var' || value == '/tmp');
}

/// Validates a path stored in Butlerly's private evidence tree.
///
/// The path may not escape [root], and no existing component may be a
/// symbolic link. The latter matters even when callers enumerate with
/// `followLinks: false`: opening a path with a symlinked parent would still
/// follow that link and could read or overwrite data outside the evidence
/// directory.
Future<String> validateEvidencePath(
  Directory root,
  String relative, {
  String message = 'Unsafe evidence path.',
}) async {
  final normalized = normalizeEvidencePath(relative, message: message);

  await rejectEvidenceRoot(root, message: message);

  var current = root.path;
  for (final component in path.split(normalized)) {
    if (component.isEmpty || component == '.') continue;
    current = path.join(current, component);
    if (await FileSystemEntity.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FormatException(message);
    }
  }
  return normalized;
}

/// Validates a database evidence reference.
///
/// Database references use the same safe relative-path contract as backup
/// entries. The evidence store normalizes these paths before resolving them,
/// so nested references remain readable while traversal and symlink escapes
/// are rejected consistently.
Future<String> validateEvidenceReferencePath(
  Directory root,
  String relative, {
  String message = 'Unsafe evidence reference.',
}) async {
  return validateEvidencePath(root, relative, message: message);
}

/// Normalizes a stored relative path without consulting the filesystem.
///
/// Backup paths must have the same safety semantics on every host. In
/// particular, a backslash is treated as a separator even on POSIX so that a
/// package made on macOS cannot smuggle `..\` traversal into Windows.
String normalizeEvidencePath(
  String relative, {
  String message = 'Unsafe evidence path.',
}) {
  final portableRelative = relative.replaceAll('\\', '/');
  final components = portableRelative.split('/');
  if (relative.trim().isEmpty ||
      relative.contains('\u0000') ||
      portableRelative.startsWith('/') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(portableRelative) ||
      components.any((component) => component == '..')) {
    throw FormatException(message);
  }
  final normalized = path.posix.normalize(portableRelative);
  if (normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      path.posix.isAbsolute(normalized)) {
    throw FormatException(message);
  }
  return normalized;
}

/// Rejects a symbolic link at the evidence-root path before traversal.
Future<void> rejectEvidenceRoot(
  Directory root, {
  String message = 'Unsafe evidence path.',
}) async {
  if (await FileSystemEntity.type(root.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw FormatException(message);
  }
}

/// Rejects symbolic links anywhere in an existing private tree before a
/// recursive mutation. A non-following directory listing alone is not enough:
/// a later recursive delete or rename can still cross a linked component.
Future<void> rejectEvidenceTree(
  Directory root, {
  String message = 'Unsafe evidence tree.',
}) async {
  await rejectEvidenceRoot(root, message: message);
  if (!await root.exists()) return;
  try {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw FormatException(message);
      }
    }
  } on FileSystemException {
    // A concurrent lock-protected restore can replace an empty root between
    // the existence check and enumeration. Treat an already-absent root as a
    // safe no-op; preserve genuine filesystem failures.
    if (await root.exists()) rethrow;
  }
}

/// Returns a portable collision key for an evidence path.
///
/// Butlerly runs on case-sensitive and case-insensitive filesystems. Backups
/// must not contain two names that are distinct on the source machine but
/// resolve to one file on the destination machine.
String evidencePathKey(String normalized) => normalized.toLowerCase();

/// Rejects symbolic links while copying an evidence tree.
Future<void> rejectEvidenceLink(FileSystemEntity entity) async {
  if (entity is Link) {
    throw const FormatException(
      'Evidence tree contains an unsupported symbolic link.',
    );
  }
}
