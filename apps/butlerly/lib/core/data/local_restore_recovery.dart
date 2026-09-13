import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:path/path.dart' as path;

Future<void> recoverInterruptedLocalRestore(
  LocalDatabase database,
  LocalDataManager localDataManager,
) async {
  await database.database.delete('restore_context');

  final root = await localDataManager.evidenceDirectory();
  final journal = File('${root.path}.restore-journal.json');
  if (!await journal.exists()) return;

  Map<String, Object?>? data;
  try {
    final decoded = jsonDecode(await journal.readAsString());
    if (decoded is Map) data = decoded.cast<String, Object?>();
  } on Exception {
    // A torn journal is recoverable from the durable DB marker and the
    // deterministic recovery-directory names below.
  }

  final committedRows = await database.database.query('restore_commits');
  final committed = committedRows.isNotEmpty;
  final recovery = await _discoverRecoveryDirectories(root);

  final journalPrevious = data?['previousPath'] as String?;
  final journalStaging = data?['stagingPath'] as String?;
  final previousCandidates = <Directory>[
    if (journalPrevious != null) Directory(journalPrevious),
    ...recovery.previous,
  ];
  final stagingCandidates = <Directory>[
    if (journalStaging != null) Directory(journalStaging),
    ...recovery.staging,
  ];
  final previous = await _newestExisting(previousCandidates);
  final stagingExists = await _anyExists(stagingCandidates);

  if (committed) {
    for (final directory in {...previousCandidates, ...stagingCandidates}) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    await database.database.delete('restore_commits');
    if (await journal.exists()) await journal.delete();
    return;
  }

  if (previous != null) {
    if (await root.exists()) await root.delete(recursive: true);
    await previous.rename(root.path);
  } else if (!stagingExists && await root.exists()) {
    // A journal exists, no DB commit exists, no original tree was retained,
    // and the staging path no longer exists. The only possible live root is
    // the uncommitted restored tree, so remove it.
    await root.delete(recursive: true);
  }

  for (final directory in {...previousCandidates, ...stagingCandidates}) {
    if (directory.path == previous?.path) continue;
    if (await directory.exists()) await directory.delete(recursive: true);
  }
  if (await journal.exists()) await journal.delete();
}

Future<_RecoveryDirectories> _discoverRecoveryDirectories(Directory root) async {
  final previous = <Directory>[];
  final staging = <Directory>[];
  final parent = root.parent;
  if (!await parent.exists()) return _RecoveryDirectories(previous, staging);
  final base = path.basename(root.path);
  await for (final entity in parent.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final name = path.basename(entity.path);
    if (name.startsWith('$base.restore-previous-')) {
      previous.add(entity);
    } else if (name.startsWith('$base.restore-')) {
      staging.add(entity);
    }
  }
  return _RecoveryDirectories(previous, staging);
}

Future<Directory?> _newestExisting(Iterable<Directory> candidates) async {
  Directory? newest;
  DateTime? newestModified;
  final seen = <String>{};
  for (final candidate in candidates) {
    if (!seen.add(candidate.path) || !await candidate.exists()) continue;
    final modified = (await candidate.stat()).modified;
    if (newest == null || modified.isAfter(newestModified!)) {
      newest = candidate;
      newestModified = modified;
    }
  }
  return newest;
}

Future<bool> _anyExists(Iterable<Directory> candidates) async {
  final seen = <String>{};
  for (final candidate in candidates) {
    if (seen.add(candidate.path) && await candidate.exists()) return true;
  }
  return false;
}

final class _RecoveryDirectories {
  const _RecoveryDirectories(this.previous, this.staging);

  final List<Directory> previous;
  final List<Directory> staging;
}
