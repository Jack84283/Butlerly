import 'dart:async';
import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:file_selector/file_selector.dart';
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
    final documents = Directory(path.join(root.path, 'documents'))
      ..createSync();
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
      await File(
        path.join(evidence.path, 'captured-during-restore.bin'),
      ).writeAsString('new evidence', flush: true);
    });

    await Future.wait<void>([restoreFuture.then((_) {}), mutationFuture]);

    expect(mutationObservedCompletedRestore, isTrue);
    final captured = File(
      path.join(evidence.path, 'captured-during-restore.bin'),
    );
    expect(await captured.exists(), isTrue);
    expect(await captured.readAsString(), 'new evidence');
  });

  test(
    'unpublished evidence survives restore and publishes file with metadata',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-preserve-publish-restore-',
      );
      final documents = Directory(path.join(root.path, 'documents'))
        ..createSync();
      final evidence = Directory(path.join(root.path, 'evidence'))
        ..createSync();
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
      final finance = FinanceServices(
        SqliteTransactionRepository(database.persistenceDatabase),
        SqlitePaymentSourceRepository(database.persistenceDatabase),
        SqliteMerchantRepository(database.persistenceDatabase),
        SqliteCategoryRepository(database.persistenceDatabase),
        SqliteTagRepository(database.persistenceDatabase),
        SqliteEvidenceRepository(database.persistenceDatabase),
        SqliteUserPreferenceRepository(database.persistenceDatabase),
      );
      final store = LocalEvidenceStore(data, finance);
      final manager = LocalBackupManager(database, data);
      final backup = File(
        path.join(root.path, 'before-capture.butlerlybackup'),
      );
      await manager.createBackup(backup);

      final source = File(path.join(root.path, 'statement.pdf'));
      await source.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      final preserved = await store.preserve(
        XFile(source.path, name: 'statement.pdf', mimeType: 'application/pdf'),
      );
      final pending = await store.fileForPreserved(preserved);
      expect(pending, isNotNull);
      expect(await pending!.exists(), isTrue);
      expect(path.isWithin(evidence.path, pending.path), isFalse);

      // Replace is allowed to swap/delete the live evidence root, but it must
      // not destroy a capture that has not yet published its SQLite metadata.
      await manager.restore(backup, mode: LocalRestoreMode.replace);
      expect(await pending.exists(), isTrue);

      final stored = await store.storePreservedStatement(preserved);
      expect(stored, isNotNull);
      expect(await pending.exists(), isFalse);
      final live = await store.fileFor(stored!);
      expect(live, isNotNull);
      expect(await live!.exists(), isTrue);
      expect(await live.readAsBytes(), <int>[1, 2, 3, 4]);

      final rows = await database.database.query(
        'evidence_items',
        where: 'id = ?',
        whereArgs: [stored.id.value],
      );
      expect(rows, hasLength(1));
      expect(rows.single['local_file_name'], preserved.localFileName);
    },
  );

  test('erase all waits for restore and leaves final state erased', () async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-restore-erase-lock-',
    );
    final documents = Directory(path.join(root.path, 'documents'))
      ..createSync();
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
    await File(
      path.join(evidence.path, 'restored-evidence.bin'),
    ).writeAsString('backup evidence', flush: true);
    final backup = File(
      path.join(root.path, 'restore-then-erase.butlerlybackup'),
    );
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
