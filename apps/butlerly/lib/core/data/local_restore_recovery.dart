import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';

Future<void> recoverInterruptedLocalRestore(
  LocalDatabase database,
  LocalDataManager localDataManager,
) async {
  // A restore cutoff is valid only while one Merge operation is actively
  // running. Clear any value left behind by a process termination before
  // normal application work can delete relationship rows.
  await database.database.delete('restore_context');

  final root = await localDataManager.evidenceDirectory();
  final journal = File('${root.path}.restore-journal.json');
  if (!await journal.exists()) return;

  Map<String, Object?> data;
  try {
    final decoded = jsonDecode(await journal.readAsString());
    if (decoded is! Map) throw const FormatException();
    data = decoded.cast<String, Object?>();
  } on Exception {
    return;
  }

  final operationId = data['operationId'] as String?;
  final previousPath = data['previousPath'] as String?;
  final stagingPath = data['stagingPath'] as String?;
  if (operationId == null) return;

  final committed = await database.database.query(
    'restore_commits',
    columns: ['operation_id'],
    where: 'operation_id = ?',
    whereArgs: [operationId],
    limit: 1,
  );
  final previous = previousPath == null ? null : Directory(previousPath);
  final staging = stagingPath == null ? null : Directory(stagingPath);

  if (committed.isNotEmpty) {
    if (previous != null && await previous.exists()) {
      await previous.delete(recursive: true);
    }
    if (staging != null && await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await database.database.delete(
      'restore_commits',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
    await journal.delete();
    return;
  }

  // No committed DB marker means the filesystem side must be rolled back.
  // This intentionally relies on actual directory state rather than only the
  // journal phase so a crash between two journal writes is still recoverable.
  if (previous != null && await previous.exists()) {
    if (await root.exists()) await root.delete(recursive: true);
    await previous.rename(root.path);
  } else if (staging != null && !await staging.exists() && await root.exists()) {
    // There was no previous evidence tree and the staging tree has already
    // been renamed into place, so remove the uncommitted restored tree.
    await root.delete(recursive: true);
  }

  if (staging != null && await staging.exists()) {
    await staging.delete(recursive: true);
  }
  if (await journal.exists()) await journal.delete();
}
