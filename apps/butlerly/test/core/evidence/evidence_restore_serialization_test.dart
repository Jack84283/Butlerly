import 'dart:async';
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

  test('erase all waits for restore and leaves final state erased', () async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-restore-erase-lock-',
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
    final old = DateTime.utc(2025, 1, 1).toIso8601String();
    await database.database.insert('transactions', {
      'id': 'tx-restore-before-erase',
      'unknown_time_reason': 'unknown',
      'amount_coefficient': '100',
      'amount_scale': 2,
      'currency': 'USD',
      'direction': 'expense',
      'source_type': 'manual',
      'status': 'active',
      'created_at': old,
      'updated_at': old,
    });
    await File(path.join(evidence.path, 'restored-evidence.bin'))
        .writeAsString('backup evidence', flush: true);
    final backup = File(path.join(root.path, 'restore-then-erase.butlerlybackup'));
    await manager.createBackup(backup);

    // Hold the mutation boundary so restore and erase can be deterministically
    // queued in that order. Once released, restore must finish before eraseAll
    // starts, making erase the final durable operation.
    final releaseBlocker = Completer<void>();
    final blockerStarted = Completer<void>();
    final blocker = EvidenceMutationLock.runExclusive(() async {
      blockerStarted.complete();
      await releaseBlocker.future;
    });
    await blockerStarted.future;

    var restoreCompleted = false;
    final restoreFuture = manager
        .restore(backup, mode: LocalRestoreMode.merge)
        .whenComplete(() => restoreCompleted = true);
    var eraseObservedCompletedRestore = false;
    final eraseFuture = data.eraseAll().whenComplete(() {
      eraseObservedCompletedRestore = restoreCompleted;
    });

    releaseBlocker.complete();
    await blocker;
    await restoreFuture;
    await eraseFuture;

    expect(eraseObservedCompletedRestore, isTrue);
    expect(await database.database.query('transactions'), isEmpty);
    expect(await database.database.query('evidence_items'), isEmpty);
    expect(await evidence.exists(), isFalse);
  });
}
