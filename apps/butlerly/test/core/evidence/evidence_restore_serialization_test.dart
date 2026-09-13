import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('evidence mutation waits until merge restore fully completes', () async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-restore-evidence-lock-',
    );
    final documents = Directory(path.join(root.path, 'documents'))..createSync();
    final evidence = Directory(path.join(root.path, 'evidence'))..createSync();
    final database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    addTearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });

    final data = LocalDataManager(
      database,
      documentsDirectory: documents,
      localEvidenceDirectory: evidence,
    );
    final manager = LocalBackupManager(database, data);
    final backup = File(path.join(root.path, 'empty.butlerlybackup'));
    await manager.createBackup(backup);

    var restoreCompleted = false;
    final restoreFuture = manager
        .restore(backup, mode: LocalRestoreMode.merge)
        .whenComplete(() => restoreCompleted = true);

    var mutationObservedCompletedRestore = false;
    final mutationFuture = EvidenceMutationLock.runExclusive(() async {
      mutationObservedCompletedRestore = restoreCompleted;
      await File(path.join(evidence.path, 'captured-during-restore.bin'))
          .writeAsString('new evidence', flush: true);
    });

    await Future.wait<void>([
      restoreFuture.then((_) {}),
      mutationFuture,
    ]);

    expect(mutationObservedCompletedRestore, isTrue);
    final captured = File(
      path.join(evidence.path, 'captured-during-restore.bin'),
    );
    expect(await captured.exists(), isTrue);
    expect(await captured.readAsString(), 'new evidence');
  });
}
