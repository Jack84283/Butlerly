import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/restore_recovery_state.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:path/path.dart' as path;

Future<void> recoverInterruptedLocalRestore(
  LocalDatabase database,
  LocalDataManager localDataManager, {
  RestoreRecoveryState? recoveryState,
}) async {
  final state = recoveryState ?? RestoreRecoveryState(localDataManager);

  // A process termination can leave merge-only trigger context behind. Never
  // allow that context to affect ordinary user edits after startup.
  await database.database.delete('restore_context');

  final root = await localDataManager.evidenceDirectory();
  final journal = File('${root.path}.restore-journal.json');
  final originStateFile = File('${root.path}.restore-origin.json');
  final originState = await _readOriginState(originStateFile);

  if (!await journal.exists()) {
    // No engine journal means there is no pre-commit filesystem operation left
    // to reconcile. A wrapper intent can still prove that engine activation
    // completed but post-activation validation/refresh never did.
    await database.database.delete('restore_commits');
    if (originState.present) {
      if (!originState.valid) {
        await state.markUnknownRequired(
          operationId: 'unknown',
          reason: 'unreadable-restore-origin-state',
        );
        return;
      }
      if (originState.activationPending) {
        await _markRecoveryRequired(
          state,
          operationId: originState.operationId!,
          safetyBackupPath: originState.safetyBackupPath,
          reason: 'post-activation-validation-pending',
          retryCurrentState: true,
        );
        return;
      }
      await _deleteOriginStateArtifacts(originStateFile);
    }
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
  final journalPreviousDirectory = journalPrevious == null
      ? null
      : Directory(journalPrevious);
  final journalStagingDirectory = journalStaging == null
      ? null
      : Directory(journalStaging);

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
      journalOperationId == committedOperationId
          ? journalStagingDirectory
          : null,
    );
    for (final directory in cleanup) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    if (await journal.exists()) await journal.delete();
    await database.database.delete(
      'restore_commits',
      where: 'operation_id = ?',
      whereArgs: [committedOperationId],
    );

    // The engine commit is only one half of the orchestration contract. If the
    // wrapper intent remains, validation/runtime refresh did not complete before
    // termination; keep the live state but block ordinary use until it is proven.
    if (originState.present) {
      if (!originState.valid) {
        await state.markUnknownRequired(
          operationId: committedOperationId,
          reason: 'unreadable-restore-origin-state',
        );
        return;
      }
      if (originState.activationPending) {
        await _markRecoveryRequired(
          state,
          operationId: originState.operationId!,
          safetyBackupPath: originState.safetyBackupPath,
          reason: 'post-activation-validation-pending',
          retryCurrentState: true,
        );
        return;
      }
      await _deleteOriginStateArtifacts(originStateFile);
    }
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
    await _markFromOriginOrUnknown(
      state,
      originState,
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
  } else if (originState.present && originState.valid) {
    if (originState.rootExisted == false) {
      // The wrapper persisted this fact before invoking the live engine.
      if (await root.exists()) await root.delete(recursive: true);
    } else if (journalPhase == 'evidenceActivated' ||
        journalPhase == 'dbWriting') {
      // The original root existed, so an activated restore must have produced a
      // deterministic previous directory. Its absence means evidence was lost
      // or externally altered; never substitute the uncommitted live tree.
      await _markRecoveryRequired(
        state,
        operationId: originState.operationId ?? journalOperationId ?? 'unknown',
        safetyBackupPath: originState.safetyBackupPath,
        reason: 'missing-previous-evidence-recovery',
        retryCurrentState: false,
      );
      return;
    }
    // In prepared phase activation had not happened, so the live root is still
    // the original tree and may be preserved safely.
  } else if (originState.present && !originState.valid) {
    await state.markUnknownRequired(
      operationId: journalOperationId ?? 'unknown',
      reason: 'unreadable-restore-origin-state',
    );
    return;
  } else if (data != null && journalPhase == 'prepared') {
    // Even without a current-build origin sidecar, a complete prepared journal
    // proves evidence activation had not started. Keeping the live tree is safe.
  } else {
    // Never infer that a missing previous directory means the original evidence
    // root was absent. The same shape can be produced by lost/corrupt recovery
    // material, so destructive inference is not safe.
    await state.markUnknownRequired(
      operationId: journalOperationId ?? 'unknown',
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
  await _deleteOriginStateArtifacts(originStateFile);
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

Future<_OriginState> _readOriginState(File file) async {
  final temporary = File('${file.path}.tmp');
  final previous = File('${file.path}.previous');
  final mainExists = await file.exists();
  final temporaryExists = await temporary.exists();
  final previousExists = await previous.exists();

  // Main + tmp proves a replacement started but did not complete. The main file
  // may describe the prior restore operation, so trusting it could select the
  // wrong safety snapshot. Fail closed instead. Main + previous (without tmp)
  // means the atomic rename completed and only rollback cleanup was interrupted.
  if (mainExists && temporaryExists) return const _OriginState.invalid();
  if (mainExists) return _parseOriginState(file);
  if (!temporaryExists && !previousExists) return const _OriginState.absent();
  if (temporaryExists && previousExists) return const _OriginState.invalid();
  return _parseOriginState(temporaryExists ? temporary : previous);
}

Future<_OriginState> _parseOriginState(File file) async {
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return const _OriginState.invalid();
    final data = decoded.cast<String, Object?>();
    final rootExisted = data['rootExisted'];
    final operationId = data['operationId'];
    final safetyBackupPath = data['safetyBackupPath'];
    final activationPending = data['activationPending'];
    if (rootExisted is! bool ||
        operationId is! String ||
        operationId.isEmpty ||
        safetyBackupPath is! String ||
        safetyBackupPath.isEmpty ||
        activationPending is! bool) {
      return const _OriginState.invalid();
    }
    return _OriginState(
      present: true,
      valid: true,
      rootExisted: rootExisted,
      operationId: operationId,
      safetyBackupPath: safetyBackupPath,
      activationPending: activationPending,
    );
  } on Exception {
    return const _OriginState.invalid();
  }
}

Future<void> _markFromOriginOrUnknown(
  RestoreRecoveryState state,
  _OriginState originState, {
  required String operationId,
  required String reason,
}) async {
  if (originState.present && originState.valid) {
    await _markRecoveryRequired(
      state,
      operationId: originState.operationId ?? operationId,
      safetyBackupPath: originState.safetyBackupPath,
      reason: reason,
      retryCurrentState: false,
    );
    return;
  }
  await state.markUnknownRequired(operationId: operationId, reason: reason);
}

Future<void> _markRecoveryRequired(
  RestoreRecoveryState state, {
  required String operationId,
  required String? safetyBackupPath,
  required String reason,
  required bool retryCurrentState,
}) async {
  if (safetyBackupPath == null || safetyBackupPath.isEmpty) {
    await state.markUnknownRequired(operationId: operationId, reason: reason);
    return;
  }
  await state.markRequired(
    operationId: operationId,
    safetyBackup: File(safetyBackupPath),
    reason: reason,
    retryCurrentState: retryCurrentState,
  );
}

Future<void> _deleteOriginStateArtifacts(File file) async {
  for (final candidate in <File>[
    file,
    File('${file.path}.tmp'),
    File('${file.path}.previous'),
  ]) {
    try {
      if (await candidate.exists()) await candidate.delete();
    } catch (_) {
      // A stale wrapper intent is harmless once one coherent state is proven.
    }
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

Future<_RecoveryDirectories> _discoverRecoveryDirectories(
  Directory root,
) async {
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
  const _OriginState({
    required this.present,
    required this.valid,
    required this.rootExisted,
    required this.operationId,
    required this.safetyBackupPath,
    required this.activationPending,
  });

  const _OriginState.absent()
    : present = false,
      valid = false,
      rootExisted = null,
      operationId = null,
      safetyBackupPath = null,
      activationPending = false;

  const _OriginState.invalid()
    : present = true,
      valid = false,
      rootExisted = null,
      operationId = null,
      safetyBackupPath = null,
      activationPending = false;

  final bool present;
  final bool valid;
  final bool? rootExisted;
  final String? operationId;
  final String? safetyBackupPath;
  final bool activationPending;
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
