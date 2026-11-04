import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_gateway.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/raw_backup_service.dart';
import 'package:butlerly/core/data/raw_merge_service.dart';
import 'package:butlerly/core/data/raw_restore_service.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory root;
  late Directory databaseDirectory;
  late Directory evidence;
  late LocalDatabase database;
  late RawBackupService backups;
  late RawRestoreService restores;

  Future<void> setProbe(String value) async {
    await database.database.insert('restore_probe', {
      'id': 'original',
      'value': value,
    });
  }

  Future<String> getProbe() async {
    final rows = await database.database.query(
      'restore_probe',
      columns: ['value'],
      where: 'id = ?',
      whereArgs: ['original'],
    );
    return rows.single['value']! as String;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('butlerly-replace-test-');
    databaseDirectory = Directory(path.join(root.path, 'db'))
      ..createSync(recursive: true);
    evidence = Directory(path.join(root.path, 'evidence'))
      ..createSync(recursive: true);
    database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: databaseDirectory.path,
    );
    await database.initialize();
    await database.database.execute(
      'CREATE TABLE restore_probe (id TEXT PRIMARY KEY, value TEXT)',
    );
    backups = RawBackupService(
      database,
      LocalDataManager(database, localEvidenceDirectory: evidence),
    );
    restores = RawRestoreService(database, backups);
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'Replace restores original SQLite records and attachment bytes',
    () async {
      final originalPersistence = database.persistenceDatabase;
      await setProbe('saved');
      final receipt = File(path.join(evidence.path, 'receipt.bin'));
      await receipt.writeAsBytes([0, 11, 22, 33]);
      final archive = File(path.join(root.path, 'original.butlerly'));
      await backups.createBackup(
        archive,
        password: 'correct horse battery staple',
      );

      await database.database.update(
        'restore_probe',
        {'value': 'newer-live-value'},
        where: 'id = ?',
        whereArgs: ['original'],
      );
      await receipt.writeAsBytes([9, 8, 7]);
      final inspection = await restores.restoreReplace(
        archive,
        password: 'correct horse battery staple',
      );

      expect(inspection.attachmentCount, 1);
      expect(await getProbe(), 'saved');
      expect(await receipt.readAsBytes(), [0, 11, 22, 33]);
      expect(
        identical(originalPersistence, database.persistenceDatabase),
        isTrue,
      );
      expect(
        await File(
          path.join(databaseDirectory.path, '.raw-restore-journal.json'),
        ).exists(),
        isFalse,
      );
    },
  );

  test('failure after old DB moved rolls back the exact live state', () async {
    await setProbe('saved');
    final receipt = File(path.join(evidence.path, 'receipt.bin'));
    await receipt.writeAsBytes([1, 2, 3]);
    final archive = File(path.join(root.path, 'original.butlerly'));
    await backups.createBackup(
      archive,
      password: 'correct horse battery staple',
    );
    await database.database.update(
      'restore_probe',
      {'value': 'must-stay-live'},
      where: 'id = ?',
      whereArgs: ['original'],
    );
    await receipt.writeAsBytes([7, 8, 9]);

    await expectLater(
      restores.restoreReplace(
        archive,
        password: 'correct horse battery staple',
        onStage: (stage) async {
          if (stage == 'original SQLite preserved') {
            throw StateError('injected restore interruption');
          }
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(await getProbe(), 'must-stay-live');
    expect(await receipt.readAsBytes(), [7, 8, 9]);
    expect(
      await File(
        path.join(databaseDirectory.path, '.raw-restore-journal.json'),
      ).exists(),
      isFalse,
    );
  });

  test(
    'production gateway uses raw backup and Replace without rule validation',
    () async {
      await setProbe('archived');
      final manager = LocalDataManager(
        database,
        localEvidenceDirectory: evidence,
      );
      final gateway = LocalWorkspaceDataGateway(
        LocalBackupManager(database, manager),
        manager,
      );
      final archive = File(path.join(root.path, 'gateway.butlerly'));
      await gateway.createPortableBackup(
        archive.path,
        password: 'correct horse battery staple',
      );
      final preview = await gateway.inspect(
        archive.path,
        password: 'correct horse battery staple',
      );
      expect(preview.createdAtUtc, isA<DateTime>());
      await database.database.update(
        'restore_probe',
        {'value': 'changed-locally'},
        where: 'id = ?',
        whereArgs: ['original'],
      );
      var businessRefreshCalled = false;
      final result = await gateway.restore(
        archive.path,
        mode: LocalRestoreMode.replace,
        password: 'correct horse battery staple',
        postActivationRefresh: () async {
          businessRefreshCalled = true;
          throw StateError('Business validation must not run during restore.');
        },
      );
      expect(result.mode, LocalRestoreMode.replace);
      expect(businessRefreshCalled, isFalse);
      expect(await getProbe(), 'archived');
    },
  );

  test('Merge keeps local changes, imports missing rows and preserves files',
      () async {
    await setProbe('archived-value');
    await database.database.insert('restore_probe', {
      'id': 'backup-only',
      'value': 'from-backup',
    });
    final shared = File(path.join(evidence.path, 'shared.bin'));
    final fromBackup = File(path.join(evidence.path, 'from-backup.bin'));
    await shared.writeAsBytes([1, 2, 3]);
    await fromBackup.writeAsBytes([4, 5, 6]);
    final archive = File(path.join(root.path, 'merge-source.butlerly'));
    await backups.createBackup(
      archive,
      password: 'correct horse battery staple',
    );

    await database.database.update(
      'restore_probe',
      {'value': 'local-wins'},
      where: 'id = ?',
      whereArgs: ['original'],
    );
    await database.database.delete(
      'restore_probe',
      where: 'id = ?',
      whereArgs: ['backup-only'],
    );
    await database.database.insert('restore_probe', {
      'id': 'local-only',
      'value': 'new-local',
    });
    await shared.writeAsBytes([7, 8, 9]);
    await fromBackup.delete();
    final localFile = File(path.join(evidence.path, 'local-only.bin'));
    await localFile.writeAsBytes([10]);

    final merged = await RawMergeService(database, backups, restores)
        .restoreMerge(archive, password: 'correct horse battery staple');
    expect(merged.recordCount, greaterThan(0));
    expect(await getProbe(), 'local-wins');
    final rows = await database.database.query('restore_probe');
    expect(rows.map((row) => row['id']).toSet(), {
      'original',
      'backup-only',
      'local-only',
    });
    expect(await shared.readAsBytes(), [7, 8, 9]);
    expect(await fromBackup.readAsBytes(), [4, 5, 6]);
    expect(await localFile.readAsBytes(), [10]);
  });

  test('Merge respects local deletion tombstones', () async {
    await setProbe('archived-value');
    await database.database.insert('restore_probe', {
      'id': 'deleted-locally',
      'value': 'do-not-resurrect',
    });
    final archive = File(path.join(root.path, 'merge-tombstone.butlerly'));
    await backups.createBackup(
      archive,
      password: 'correct horse battery staple',
    );
    await database.database.delete(
      'restore_probe',
      where: 'id = ?',
      whereArgs: ['deleted-locally'],
    );
    await database.database.insert('entity_tombstones', {
      'entity_type': 'restore_probe',
      'entity_id': 'deleted-locally',
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    });

    await RawMergeService(database, backups, restores).restoreMerge(
      archive,
      password: 'correct horse battery staple',
    );
    final rows = await database.database.query(
      'restore_probe',
      where: 'id = ?',
      whereArgs: ['deleted-locally'],
    );
    expect(rows, isEmpty);
  });

  test('wrong password leaves live database and files untouched', () async {
    await setProbe('local');
    final archive = File(path.join(root.path, 'original.butlerly'));
    await backups.createBackup(
      archive,
      password: 'correct horse battery staple',
    );
    await expectLater(
      restores.restoreReplace(archive, password: 'wrong password'),
      throwsA(isA<Exception>()),
    );
    expect(await getProbe(), 'local');
  });

  test(
    'startup recovery restores previous SQLite after interrupted switch',
    () async {
      await setProbe('existing');
      final receipt = File(path.join(evidence.path, 'receipt.bin'));
      await receipt.writeAsBytes([3, 1, 4]);
      final currentDb = File(database.persistenceDatabase.path);
      await database.close();

      const id = '1700000000000000';
      final previous = File('${currentDb.path}.raw-restore-previous-$id');
      final previousEvidence = Directory(
        '${evidence.path}.raw-restore-previous-$id',
      );
      await currentDb.rename(previous.path);
      await evidence.rename(previousEvidence.path);
      await currentDb.writeAsBytes([0, 0, 0, 0], flush: true);
      await evidence.create();
      await File(path.join(evidence.path, 'receipt.bin')).writeAsBytes([99]);

      final journal = File(
        path.join(databaseDirectory.path, '.raw-restore-journal.json'),
      );
      await journal.writeAsString(
        jsonEncode({
          'format': 'butlerly-raw-restore',
          'operationId': id,
          'hadEvidence': true,
        }),
        flush: true,
      );
      await RawRestoreService.recoverInterruptedReplace(
        liveDatabase: currentDb,
        evidenceDirectory: evidence,
      );
      await database.initialize();
      expect(await getProbe(), 'existing');
      expect(await receipt.readAsBytes(), [3, 1, 4]);
      expect(await journal.exists(), isFalse);
    },
  );
}
