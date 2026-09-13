import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/restore_recovery_state.dart';
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
  final originStateFile = File('${root.path}.restore-origin.json');
  if (!await journal.exists()) {
    // With no recovery journal there is no filesystem operation to reconcile.
    // Any commit marker/origin marker is stale cleanup residue and must not make
    // a later unrelated restore look committed or inherit old recovery state.
    await database.database.delete('restore_commits');
    await _deleteFileBestEffort(originStateFile);
    await _deleteFileBestEffort(File('${originStateFile.path}.tmp'));
    return;
  }

  Map<String, Object?>? data;
  try {
    final decoded = jsonDecode(await journal.readAsString());
    if (decoded is Map) data = decoded.cast<String, Object?>();
  } on Exception {
    // A torn journal is recoverable only when durable state identifies one
    // operation unambiguously. Never guess among multiple evidence trees.
  }

  final originState = await _readOriginState(originStateFile);
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
  final journalPhase = data?['phase'] as String?;
  final journalPreviousDirectory =
      journalPrevious == null ? null : Directory(journalPrevious);
  final journalStagingDirectory =
      journalStaging == null ? null : Directory(journalStaging);

  if (committed) {
    // DB commit is authoritative: keep the live evidence tree. Cleanup is
    // scoped to the committed operation so stale artifacts from another crash
    // cannot be destroyed accidentally.
    final cleanup = _directoriesForOperation(
      committedOperationId,
      recovery,
      journalOperationId == committedOperationId
          ? journalPreviousDirectory
          : null,
      journalOperationId == committedOperationId ? journalStagingDirectory : null,
    );
    for (final directory in cleanup) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    if (await journal.exists()) await journal.delete();
    await _deleteFileBestEffort(originStateFile);
    await database.database.delete(
      'restore_commits',
      where: 'operation_id = ?',
      whereArgs: [committedOperationId],
    );
    return;
  }

  final selection = await _selectPreviousDirectory(
    journalOperationId: journalOperationId,
    journalPrevious: journalPreviousDirectory,
    recovery: recovery,
  );

  if (selection.ambiguous) {
    // The application cannot prove which filesystem tree belongs with the live
    // database. Preserve every candidate and persist a fail-closed marker. Do
    // not delete the journal/commit evidence that a recovery workflow may need.
    await _markRecoveryRequired(
      localDataManager,
      operationId: journalOperationId ?? 'unknown',
      reason: 'ambiguous-restore-recovery',
    );
    return;
  }

  final previous = selection.directory;
  if (previous != null) {
    // An original evidence tree is identified unambiguously and the DB did not
    // commit. Restore exactly that tree.
    if (await root.exists()) await root.delete(recursive: true);
    await previous.rename(root.path);
  } else if (originState.present && originState.rootExisted == false) {
    // The wrapper persisted this fact before invoking the live engine. Returning
    // to an absent evidence root is therefore deterministic, even when the
    // restore crashed after staging activation but before the DB commit.
    if (await root.exists()) await root.delete(recursive: true);
  } else if (originState.present && originState.rootExisted == true) {
    if (journalPhase == 'evidenceActivated' || journalPhase == 'dbWriting') {
      // The original root existed, so an activated restore must have produced a
      // deterministic previous directory. Its absence means evidence was lost
      // or externally altered; never substitute the uncommitted live tree.
      await _markRecoveryRequired(
        localDataManager,
        operationId: journalOperationId ?? 'unknown',
        reason: 'missing-previous-evidence-recovery',
      );
      return;
    }
    // In prepared phase activation had not happened, so the live root is still
    // the original tree and may be preserved safely.
  } else if (originState.present && originState.rootExisted == null) {
    // A sidecar exists but cannot be trusted. Its presence proves this build
    // intended to record the original state, so do not fall back to inference.
    await _markRecoveryRequired(
      localDataManager,
      operationId: journalOperationId ?? 'unknown',
      reason: 'unreadable-restore-origin-state',
    );
    return;
  } else if (_provesOriginalEvidenceWasAbsentForLegacyRestore(
    root: root,
    operationId: journalOperationId,
    previous: journalPreviousDirectory,
    staging: journalStagingDirectory,
    phase: journalPhase,
  )) {
    // Compatibility for an interrupted restore started by an earlier build that
    // did not persist restore-origin.json. The engine's deterministic paths and
    // activated phase are the strongest evidence available for that legacy run.
    if (await root.exists()) await root.delete(recursive: true);
  } else if (data == null && recovery.previous.isEmpty) {
    // A torn legacy journal with no previous tree cannot distinguish "prepared
    // before activation" from "activated when the original root was absent".
    await _markRecoveryRequired(
      localDataManager,
      operationId: 'unknown',
      reason: 'indeterminate-restore-recovery',
    );
    return;
  }

  // Clean only artifacts belonging to the identified operation. If the journal
  // is torn and there was exactly one previous tree, its operation suffix is the
  // only identity we can trust; unrelated stale candidates remain untouched.
  final operationId =
      journalOperationId ?? _operationIdFromPrevious(root, previous);
  if (operationId != null) {
    final cleanup = _directoriesForOperation(
      operationId,
      recovery,
      journalOperationId == operationId ? journalPreviousDirectory : null,
      journalOperationId == operationId ? journalStagingDirectory : null,
    );
    for (final directory in cleanup) {
      if (directory.path == previous?.path) continue;
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  if (await journal.exists()) await journal.delete();
  await _deleteFileBestEffort(originStateFile);
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
  // More than one match is ambiguous and must never be resolved by Set order.
  final matches = <String>[];
  for (final operationId in markerIds) {
    final suffix = '-$operationId';
    final matchesRecoveryDirectory = <Directory>[
      ...recovery.previous,
      ...recovery.staging,
    ].any((directory) => directory.path.endsWith(suffix));
    if (matchesRecoveryDirectory) matches.add(operationId);
  }
  return matches.length == 1 ? matches.single : null;
}

Future<_PreviousSelection> _selectPreviousDirectory({
  required String? journalOperationId,
  required Directory? journalPrevious,
  required _RecoveryDirectories recovery,
}) async {
  if (journalPrevious != null && await journalPrevious.exists()) {
    return _PreviousSelection(journalPrevious, false);
  }

  final existing = <Directory>[];
  final seen = <String>{};
  for (final directory in recovery.previous) {
    if (seen.add(directory.path) && await directory.exists()) {
      existing.add(directory);
    }
  }

  if (journalOperationId != null) {
    final suffix = '-$journalOperationId';
    final matches = existing
        .where((directory) => directory.path.endsWith(suffix))
        .toList(growable: false);
    if (matches.length == 1) return _PreviousSelection(matches.single, false);
    if (matches.length > 1) return const _PreviousSelection(null, true);
    return const _PreviousSelection(null, false);
  }

  if (existing.length == 1) return _PreviousSelection(existing.single, false);
  if (existing.length > 1) return const _PreviousSelection(null, true);
  return const _PreviousSelection(null, false);
}

bool _provesOriginalEvidenceWasAbsentForLegacyRestore({
  required Directory root,
  required String? operationId,
  required Directory? previous,
  required Directory? staging,
  required String? phase,
}) {
  if (operationId == null || previous == null || staging == null) return false;
  if (phase != 'evidenceActivated' && phase != 'dbWriting') return false;
  return previous.path == '${root.path}.restore-previous-$operationId' &&
      staging.path == '${root.path}.restore-$operationId';
}

Future<_OriginState> _readOriginState(File file) async {
  if (!await file.exists()) return const _OriginState(false, null);
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return const _OriginState(true, null);
    final value = decoded['rootExisted'];
    return value is bool
        ? _OriginState(true, value)
        : const _OriginState(true, null);
  } on Exception {
    return const _OriginState(true, null);
  }
}

Future<void> _markRecoveryRequired(
  LocalDataManager localDataManager, {
  required String operationId,
  required String reason,
}) async {
  final state = RestoreRecoveryState(localDataManager);
  await state.markUnknownRequired(operationId: operationId, reason: reason);
}

Future<void> _deleteFileBestEffort(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on Exception {
    // Recovery outcome is authoritative; stale sidecar cleanup is best effort.
  }
}

Set<Directory> _directoriesForOperation(
  String operationId,
  _RecoveryDirectories recovery,
  Directory? journalPrevious,
  Directory? journalStaging,
) {
  final suffix = '-$operationId';
  return <Directory>{
    ?journalPrevious,
    ?journalStaging,
    ...recovery.previous.where((directory) => directory.path.endsWith(suffix)),
    ...recovery.staging.where((directory) => directory.path.endsWith(suffix)),
  };
}

String? _operationIdFromPrevious(Directory root, Directory? previous) {
  if (previous == null) return null;
  final prefix = '${path.basename(root.path)}.restore-previous-';
  final name = path.basename(previous.path);
  if (!name.startsWith(prefix) || name.length == prefix.length) return null;
  return name.substring(prefix.length);
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

final class _OriginState {
  const _OriginState(this.present, this.rootExisted);

  final bool present;
  final bool? rootExisted;
}

final class _PreviousSelection {
  const _PreviousSelection(this.directory, this.ambiguous);

  final Directory? directory;
  final bool ambiguous;
}

final class _RecoveryDirectories {
  const _RecoveryDirectories(this.previous, this.staging);

  final List<Directory> previous;
  final List<Directory> staging;
}
