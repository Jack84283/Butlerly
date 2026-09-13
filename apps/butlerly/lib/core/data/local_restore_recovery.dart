import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:path/path.dart' as path;

Future<void> recoverInterruptedLocalRestore(
  LocalDatabase database,
  LocalDataManager localDataManager,
) async {
  // A process termination can leave merge-only trigger context behind. Never
  // allow that context to affect ordinary user edits after startup.
  await database.database.delete('restore_context');

  final root = await localDataManager.evidenceDirectory();
  final journal = File('${root.path}.restore-journal.json');
  if (!await journal.exists()) {
    // With no recovery journal there is no filesystem operation to reconcile.
    // Any commit marker is therefore stale cleanup residue and must not make a
    // later unrelated restore look committed.
    await database.database.delete('restore_commits');
    return;
  }

  Map<String, Object?>? data;
  try {
    final decoded = jsonDecode(await journal.readAsString());
    if (decoded is Map) data = decoded.cast<String, Object?>();
  } on Exception {
    // A torn journal is recoverable from durable DB state and deterministic
    // recovery-directory names. Never treat a parse failure as permission to
    // delete the live evidence tree.
  }

  final recovery = await _discoverRecoveryDirectories(root);
  final markerRows = await database.database.query(
    'restore_commits',
    columns: ['operation_id'],
  );
  final markerIds = markerRows
      .map((row) => row['operation_id'])
      .whereType<String>()
      .toSet();
  final journalOperationId = data?['operationId'] as String?;
  final committedOperationId = _committedOperationId(
    journalOperationId: journalOperationId,
    markerIds: markerIds,
    recovery: recovery,
  );
  final committed = committedOperationId != null;

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

  if (committed) {
    // DB commit is authoritative: keep the live evidence tree and only remove
    // recovery artifacts. Remove the journal before the matching commit marker
    // so a crash can never leave "journal present, marker absent" after success.
    for (final directory in {...previousCandidates, ...stagingCandidates}) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    if (await journal.exists()) await journal.delete();
    await database.database.delete(
      'restore_commits',
      where: 'operation_id = ?',
      whereArgs: [committedOperationId],
    );
    return;
  }

  if (previous != null) {
    // An original evidence tree exists and the DB did not commit. Restore it.
    if (await root.exists()) await root.delete(recursive: true);
    await previous.rename(root.path);
  } else {
    // Ambiguous state: the original tree may legitimately have been empty, or
    // the DB may already have committed and only its marker cleanup completed
    // before the process died. Preserve the live tree rather than risk deleting
    // evidence that belongs to committed financial records. Any unreferenced
    // files are harmless and can be cleaned by a later integrity sweep.
  }

  for (final directory in {...previousCandidates, ...stagingCandidates}) {
    if (directory.path == previous?.path) continue;
    if (await directory.exists()) await directory.delete(recursive: true);
  }
  if (await journal.exists()) await journal.delete();
  // Once filesystem recovery is complete and no journal remains, no marker can
  // be authoritative. This also clears residue from an unrelated stale marker.
  await database.database.delete('restore_commits');
}

String? _committedOperationId({
  required String? journalOperationId,
  required Set<String> markerIds,
  required _RecoveryDirectories recovery,
}) {
  if (journalOperationId != null && markerIds.contains(journalOperationId)) {
    return journalOperationId;
  }

  // If the journal is torn before its operation ID can be read, a durable DB
  // marker may still be matched safely to deterministic recovery directories.
  // This distinguishes a genuinely committed restore from an unrelated stale
  // marker without trusting "any marker exists".
  for (final operationId in markerIds) {
    final suffix = '-$operationId';
    final matchesRecoveryDirectory = <Directory>[
      ...recovery.previous,
      ...recovery.staging,
    ].any((directory) => directory.path.endsWith(suffix));
    if (matchesRecoveryDirectory) return operationId;
  }
  return null;
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

final class _RecoveryDirectories {
  const _RecoveryDirectories(this.previous, this.staging);

  final List<Directory> previous;
  final List<Directory> staging;
}
