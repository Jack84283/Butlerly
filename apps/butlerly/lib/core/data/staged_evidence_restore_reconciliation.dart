import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly_database/butlerly_database.dart' show sha256FileRange;
import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';

/// Reconciles evidence moved to the staged-deletion tree while a restore was
/// activating. Returns true when any artifact must remain available for a
/// later evidence-recovery pass.
Future<bool> reconcileStagedEvidenceAfterRestore(
  DatabaseExecutor database,
  Directory liveRoot,
  Directory stagedRoot, {
  required bool replaceRestore,
}) async {
  await rejectEvidenceRoot(liveRoot, message: 'Unsafe live evidence root.');
  await rejectEvidenceTree(stagedRoot, message: 'Unsafe staged deletion tree.');
  if (!await stagedRoot.exists()) return false;

  var unresolved = false;
  final referencedStagedPaths = <String>{};
  await for (final entity in stagedRoot.list(followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.json')) {
      continue;
    }
    // A source file may itself use the .json extension. Its manifest is then
    // the sibling with an additional .json suffix.
    if (await File('${entity.path}.json').exists()) continue;

    try {
      final decoded = jsonDecode(await entity.readAsString());
      if (decoded is! Map<String, dynamic>) {
        unresolved = true;
        continue;
      }
      final evidenceId = decoded['evidenceId'];
      final localFileName = decoded['localFileName'];
      final stagedFileName = decoded['stagedFileName'];
      final byteLength = decoded['byteLength'];
      final fingerprint = decoded['sourceFingerprint'];
      final deletionState = decoded['deletionState'];
      if (evidenceId is! String ||
          localFileName is! String ||
          stagedFileName is! String ||
          byteLength is! int ||
          byteLength < 0 ||
          fingerprint is! String ||
          fingerprint.isEmpty ||
          (deletionState != null && deletionState is! String)) {
        unresolved = true;
        continue;
      }
      if (deletionState != null &&
          deletionState != 'prepared' &&
          deletionState != 'committed') {
        unresolved = true;
        continue;
      }

      final normalizedStaged = await validateEvidencePath(
        stagedRoot,
        stagedFileName,
        message: 'Unsafe staged evidence path.',
      );
      referencedStagedPaths.add(normalizedStaged);
      final normalizedLocal = await validateEvidenceReferencePath(
        liveRoot,
        localFileName,
        message: 'Unsafe restored evidence path.',
      );
      final staged = File(path.join(stagedRoot.path, normalizedStaged));
      final live = File(path.join(liveRoot.path, normalizedLocal));
      final rows = await database.query(
        'evidence_items',
        columns: ['local_file_name'],
        where: 'id = ?',
        whereArgs: [evidenceId],
      );
      final owner = rows.isEmpty ? null : rows.first['local_file_name'];
      final ownsSource = owner == localFileName;

      if (!ownsSource) {
        if (replaceRestore || deletionState == 'committed') {
          if (await staged.exists()) await staged.delete();
          if (await entity.exists()) await entity.delete();
        } else {
          unresolved = true;
        }
        continue;
      }

      final stagedValid = await _matchesIntegrity(
        staged,
        byteLength: byteLength,
        fingerprint: fingerprint,
      );
      final liveValid = await _matchesIntegrity(
        live,
        byteLength: byteLength,
        fingerprint: fingerprint,
      );
      if (stagedValid && !await live.exists()) {
        await live.parent.create(recursive: true);
        await staged.rename(live.path);
      } else if (!stagedValid && !liveValid) {
        unresolved = true;
        continue;
      } else if (stagedValid && liveValid) {
        await staged.delete();
      } else if (!liveValid) {
        unresolved = true;
        continue;
      }
      if (await entity.exists()) await entity.delete();
    } on Object {
      unresolved = true;
    }
  }
  await for (final entity in stagedRoot.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File || entity.path.endsWith('.json')) continue;
    final relative = path.relative(entity.path, from: stagedRoot.path);
    if (!referencedStagedPaths.contains(path.normalize(relative))) {
      unresolved = true;
    }
  }
  return unresolved;
}

Future<bool> _matchesIntegrity(
  File file, {
  required int byteLength,
  required String fingerprint,
}) async {
  if (!await file.exists()) return false;
  try {
    return await file.length() == byteLength &&
        await sha256FileRange(file) == fingerprint;
  } on Object {
    return false;
  }
}
