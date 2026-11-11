import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Only records a successful local backup operation; never claims a restore
/// test occurred or that an externally saved file still exists.
@immutable
final class LocalBackupStatus {
  const LocalBackupStatus({
    required this.completedAtUtc,
    required this.missingAttachments,
  });

  final DateTime completedAtUtc;
  final bool missingAttachments;
}

final class LocalBackupStatusStore {
  const LocalBackupStatusStore({this.directoryOverride});

  /// Allows tests to use an isolated temporary directory.
  final Directory? directoryOverride;

  Future<File> _file() async {
    final directory =
        directoryOverride ?? await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'backup_status_v1.json'));
  }

  Future<LocalBackupStatus?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 ||
          decoded['completedAtUtc'] is! String ||
          decoded['missingAttachments'] is! bool) {
        return null;
      }
      final timestamp = DateTime.tryParse(decoded['completedAtUtc'] as String);
      if (timestamp == null || !timestamp.isUtc) return null;
      return LocalBackupStatus(
        completedAtUtc: timestamp,
        missingAttachments: decoded['missingAttachments'] as bool,
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> recordCompleted({required bool missingAttachments}) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'missingAttachments': missingAttachments,
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
