import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/backup_encryption.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_gateway.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/raw_backup_archive.dart';
import 'package:butlerly/core/data/raw_backup_service.dart';
import 'package:butlerly/core/data/raw_merge_service.dart';
import 'package:butlerly/core/data/raw_restore_service.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart'
    show NewerBackupSchemaException, RestoreRecoveryRequiredException;
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

  /// Build a genuine encrypted raw archive containing a prior SQLite schema.
  /// The archived database is made from real app tables, not a mocked schema.
  Future<File> archivedSchema({
    required int version,
    required String label,
  }) async {
    final oldDb = File(path.join(root.path, '$label.sqlite'));
    final quoted = oldDb.path.replaceAll("'", "''");
    await database.database.execute("VACUUM INTO '$quoted'");
    final connection = await databaseFactoryFfi.openDatabase(oldDb.path);
    try {
      if (version == 17 || version == 18) {
        // Deployment schema 19 introduces financial_profiles.
        await connection.execute('DROP TABLE financial_profiles');
      }
      if (version == 17) {
        // Deployment schema 18 introduces budgets.
        await connection.execute('DROP TABLE budgets');
      }
      await connection.execute('PRAGMA user_version = $version');
    } finally {
      await connection.close();
    }
    final plain = File(path.join(root.path, '$label.raw'));
    await const RawBackupArchive().write(
      sqliteSnapshot: oldDb,
      evidenceDirectory: evidence,
      referencedEvidencePaths: const [],
      destination: plain,
      recordCount: 1,
    );
    final encrypted = File(path.join(root.path, '$label.butlerly'));
    await const BackupEncryption().encrypt(
      plain,
      encrypted,
      password: 'correct horse battery staple',
      innerFormat: 'butlerly-raw-backup',
    );
    return encrypted;
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

  test(
    'committed Replace succeeds when prior-evidence cleanup is unsafe',
    () async {
      if (Platform.isWindows) return;
      await setProbe('from-archive');
      final archive = File(path.join(root.path, 'postcommit-cleanup.butlerly'));
      await backups.createBackup(
        archive,
        password: 'correct horse battery staple',
      );
      await database.database.update(
        'restore_probe',
        {'value': 'before-replace'},
        where: 'id = ?',
        whereArgs: ['original'],
      );
      final external = File(path.join(root.path, 'protected-external.txt'));
      await external.writeAsString('do not remove');
      Directory? oldEvidence;
      final result = await restores.restoreReplace(
        archive,
        password: 'correct horse battery staple',
        onStage: (stage) async {
          if (stage == 'restored database reopened') {
            final dirs = await evidence.parent
                .list(followLinks: false)
                .where(
                  (entry) =>
                      entry is Directory &&
                      path
                          .basename(entry.path)
                          .startsWith('evidence.raw-restore-previous-'),
                )
                .toList();
            expect(dirs, hasLength(1));
            oldEvidence = dirs.single as Directory;
            await Link(
              path.join(oldEvidence!.path, 'untrusted-link'),
            ).create(external.path);
          }
        },
      );
      expect(result.recordCount, greaterThanOrEqualTo(0));
      expect(await getProbe(), 'from-archive');
      expect(await external.readAsString(), 'do not remove');
      expect(await oldEvidence!.exists(), isTrue);
      expect(
        await File(
          path.join(databaseDirectory.path, '.raw-restore-journal.json'),
        ).exists(),
        isFalse,
      );
    },
  );

  test('a raw backup restores to an independent installation', () async {
    await setProbe('portable-snapshot');
    final sourceEvidence = File(path.join(evidence.path, 'receipt.bin'));
    await sourceEvidence.writeAsBytes([2, 4, 6, 8]);
    final archive = File(path.join(root.path, 'portable.butlerly'));
    await backups.createBackup(
      archive,
      password: 'correct horse battery staple',
    );
    final originalBytes = await archive.readAsBytes();

    // A second SQLite installation has a different app-support directory and
    // evidence directory. Nothing in the backup identifies the source device.
    final targetDirectory = Directory(path.join(root.path, 'destination-db'))
      ..createSync(recursive: true);
    final targetEvidence = Directory(
      path.join(root.path, 'destination-evidence'),
    )..createSync(recursive: true);
    final target = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: targetDirectory.path,
    );
    await target.initialize();
    try {
      final targetData = LocalDataManager(
        target,
        localEvidenceDirectory: targetEvidence,
      );
      final targetBackups = RawBackupService(target, targetData);
      final restore = RawRestoreService(target, targetBackups);
      final preview = await targetBackups.inspect(
        archive,
        password: 'correct horse battery staple',
      );
      expect(preview.createdAtUtc, isA<DateTime>());
      await restore.restoreReplace(
        archive,
        password: 'correct horse battery staple',
      );

      final sourceRows = await target.database.query('restore_probe');
      expect(sourceRows.single['value'], 'portable-snapshot');
      expect(
        await File(path.join(targetEvidence.path, 'receipt.bin')).readAsBytes(),
        [2, 4, 6, 8],
      );
      expect(await archive.readAsBytes(), originalBytes);
    } finally {
      await target.close();
    }
  });

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

  test(
    'Restore fences direct repository writes in the final activation window',
    () async {
      await setProbe('snapshot-value');
      final archive = File(path.join(root.path, 'activation-fence.butlerly'));
      await backups.createBackup(
        archive,
        password: 'correct horse battery staple',
      );
      var sawFence = false;
      await restores.restoreReplace(
        archive,
        password: 'correct horse battery staple',
        onStage: (stage) async {
          if (stage == 'restore write barrier entered') {
            sawFence = true;
            expect(() => database.database, throwsA(isA<Exception>()));
            expect(
              () => database.persistenceDatabase.connection,
              throwsA(isA<Exception>()),
            );
          }
        },
      );
      expect(sawFence, isTrue);
      expect(await getProbe(), 'snapshot-value');
      // Normal reads and writes are available again only after commit.
      await database.database.insert('restore_probe', {
        'id': 'post-restore',
        'value': 'write-now-allowed',
      });
      final rows = await database.database.query(
        'restore_probe',
        where: 'id = ?',
        whereArgs: ['post-restore'],
      );
      expect(rows.single['value'], 'write-now-allowed');
    },
  );

  test(
    'Merge keeps local changes, imports missing rows and preserves files',
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

      final merged = await RawMergeService(
        database,
        backups,
        restores,
      ).restoreMerge(archive, password: 'correct horse battery staple');
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
    },
  );

  test(
    'Merge refuses to attach imported children to conflicting local parents',
    () async {
      await database.database.execute(
        'CREATE TABLE merge_parent (id TEXT PRIMARY KEY, label TEXT NOT NULL)',
      );
      await database.database.execute(
        'CREATE TABLE merge_child (id TEXT PRIMARY KEY, '
        'parent_id TEXT NOT NULL REFERENCES merge_parent(id))',
      );
      await database.database.insert('merge_parent', {
        'id': 'same-parent-id',
        'label': 'original-category',
      });
      await database.database.insert('merge_child', {
        'id': 'backup-only-child',
        'parent_id': 'same-parent-id',
      });
      final archive = File(path.join(root.path, 'parent-conflict.butlerly'));
      await backups.createBackup(
        archive,
        password: 'correct horse battery staple',
      );
      await database.database.update(
        'merge_parent',
        {'label': 'different-local-category'},
        where: 'id = ?',
        whereArgs: ['same-parent-id'],
      );
      await database.database.delete('merge_child');

      await expectLater(
        RawMergeService(
          database,
          backups,
          restores,
        ).restoreMerge(archive, password: 'correct horse battery staple'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('referenced merge_parent identity differs'),
          ),
        ),
      );
      final parents = await database.database.query('merge_parent');
      expect(parents.single['label'], 'different-local-category');
      expect(await database.database.query('merge_child'), isEmpty);
    },
  );

  test(
    'Merge rejects an orphaned backup child instead of adopting local parent',
    () async {
      await database.database.execute(
        'CREATE TABLE orphan_parent (id TEXT PRIMARY KEY, label TEXT NOT NULL)',
      );
      await database.database.execute(
        'CREATE TABLE orphan_child (id TEXT PRIMARY KEY, '
        'parent_id TEXT NOT NULL REFERENCES orphan_parent(id))',
      );
      await database.database.insert('orphan_parent', {
        'id': 'shared-id',
        'label': 'local-parent',
      });

      // Build a deliberately damaged backup that contains a child whose
      // original parent is absent. Target SQLite has a parent with the same
      // identifier, so target-only FK checks would incorrectly pass.
      final sourceFile = File(path.join(root.path, 'orphan-source.sqlite'));
      final quoted = sourceFile.path.replaceAll("'", "''");
      await database.database.execute("VACUUM INTO '$quoted'");
      final source = await databaseFactoryFfi.openDatabase(sourceFile.path);
      try {
        await source.execute('PRAGMA foreign_keys = OFF');
        await source.insert('orphan_child', {
          'id': 'orphan-in-source',
          'parent_id': 'shared-id',
        });
        await source.delete(
          'orphan_parent',
          where: 'id = ?',
          whereArgs: ['shared-id'],
        );
        final orphans = await source.rawQuery('PRAGMA foreign_key_check');
        expect(orphans, isNotEmpty);
      } finally {
        await source.close();
      }
      final plain = File(path.join(root.path, 'orphan-source.raw'));
      await const RawBackupArchive().write(
        sqliteSnapshot: sourceFile,
        evidenceDirectory: evidence,
        referencedEvidencePaths: const [],
        destination: plain,
        recordCount: 1,
      );
      final encrypted = File(path.join(root.path, 'orphan-source.butlerly'));
      await const BackupEncryption().encrypt(
        plain,
        encrypted,
        password: 'correct horse battery staple',
        innerFormat: 'butlerly-raw-backup',
      );
      await expectLater(
        RawMergeService(
          database,
          backups,
          restores,
        ).restoreMerge(encrypted, password: 'correct horse battery staple'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('unresolved foreign-key references'),
          ),
        ),
      );
      expect(
        (await database.database.query('orphan_parent')).single['label'],
        'local-parent',
      );
      expect(await database.database.query('orphan_child'), isEmpty);
    },
  );

  test(
    'Merge aborts when a direct SQLite write arrives during staging',
    () async {
      await setProbe('archived-value');
      final archive = File(path.join(root.path, 'live-write.butlerly'));
      await backups.createBackup(
        archive,
        password: 'correct horse battery staple',
      );
      await database.database.update(
        'restore_probe',
        {'value': 'local-value'},
        where: 'id = ?',
        whereArgs: ['original'],
      );

      await expectLater(
        RawMergeService(database, backups, restores).restoreMerge(
          archive,
          password: 'correct horse battery staple',
          onStage: (stage) async {
            if (stage == 'attachment staging') {
              await database.database.insert('restore_probe', {
                'id': 'late-local-write',
                'value': 'keep-this-value',
              });
            }
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(await getProbe(), 'local-value');
      final late = await database.database.query(
        'restore_probe',
        where: 'id = ?',
        whereArgs: ['late-local-write'],
      );
      expect(late.single['value'], 'keep-this-value');
      expect(
        await File(
          path.join(databaseDirectory.path, '.raw-restore-journal.json'),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'Merge preserves a committed write from a retained connection after fence',
    () async {
      await setProbe('archived-state');
      final archive = File(path.join(root.path, 'late-after-fence.butlerly'));
      await backups.createBackup(
        archive,
        password: 'correct horse battery staple',
      );
      await database.database.update(
        'restore_probe',
        {'value': 'newer-local'},
        where: 'id = ?',
        whereArgs: ['original'],
      );
      // Simulates code that had retained a direct sqflite connection before
      // the Restore maintenance fence was enabled.
      final retained = database.database;
      var injected = false;
      await expectLater(
        RawMergeService(database, backups, restores).restoreMerge(
          archive,
          password: 'correct horse battery staple',
          onStage: (stage) async {
            if (stage == 'before transactional merge') {
              injected = true;
              await retained.insert('restore_probe', {
                'id': 'committed-after-final-revision',
                'value': 'must-not-be-lost',
              });
            }
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(injected, isTrue);
      expect(await getProbe(), 'newer-local');
      final late = await database.database.query(
        'restore_probe',
        where: 'id = ?',
        whereArgs: ['committed-after-final-revision'],
      );
      expect(late.single['value'], 'must-not-be-lost');
      expect(
        await File(
          path.join(databaseDirectory.path, '.raw-restore-journal.json'),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'Merge SQLite transaction excludes a competing independent writer',
    () async {
      if (!Platform.isLinux) return; // CI provides python3 + POSIX SQLite.
      await setProbe('backup-value');
      final archive = File(path.join(root.path, 'external-writer.butlerly'));
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
      var attempted = false;
      var pathStayedPresent = false;
      final backupFile = File(database.persistenceDatabase.path);
      await RawMergeService(database, backups, restores).restoreMerge(
        archive,
        password: 'correct horse battery staple',
        onStage: (stage) async {
          if (stage == 'original SQLite preserved') {
            pathStayedPresent = await backupFile.exists();
          }
          if (stage == 'transactional merge write lock acquired') {
            attempted = true;
            const writer =
                'import sqlite3,sys\n'
                'db=sqlite3.connect(sys.argv[1],timeout=0.1)\n'
                'db.execute("BEGIN IMMEDIATE")\n'
                'db.execute("INSERT INTO restore_probe (id,value) VALUES '
                '(?,?)",("external-late","must-not-be-lost"))\n'
                'db.commit()\n';
            final process = await Process.run('python3', [
              '-c',
              writer,
              backupFile.path,
            ]);
            expect(
              process.exitCode,
              isNot(0),
              reason:
                  'An external SQLite writer committed during the '
                  'transactionally locked Merge write window.',
            );
          }
        },
      );
      expect(attempted, isTrue);
      expect(pathStayedPresent, isTrue);
      expect(await getProbe(), 'local-wins');
      expect(
        await database.database.query(
          'restore_probe',
          where: 'id = ?',
          whereArgs: ['external-late'],
        ),
        isEmpty,
      );
    },
  );

  test('retired physical Merge entry point fails closed', () async {
    await setProbe('must-remain');
    await expectLater(
      restores.restoreReplace(
        File(path.join(root.path, 'unused-archive.butlerly')),
        password: 'unused password',
        prepareStaging: (staging, inspection) async => inspection,
      ),
      throwsA(isA<UnsupportedError>()),
    );
    expect(await getProbe(), 'must-remain');
  });

  test(
    'idle external SQLite connection resumes safely after in-place Merge',
    () async {
      if (!Platform.isLinux) return; // CI includes Python SQLite.
      await setProbe('archived-value');
      await database.database.insert('restore_probe', {
        'id': 'backup-only',
        'value': 'imported',
      });
      final archive = File(path.join(root.path, 'idle-reader.butlerly'));
      await backups.createBackup(
        archive,
        password: 'correct horse battery staple',
      );
      await database.database.delete(
        'restore_probe',
        where: 'id = ?',
        whereArgs: ['backup-only'],
      );
      // Keep a separate process's connection open across Merge. With the
      // previous rename protocol it would retain an obsolete database inode.
      const worker =
          'import sqlite3,sys\n'
          'db=sqlite3.connect(sys.argv[1],timeout=5)\n'
          'db.execute("SELECT count(*) FROM restore_probe").fetchone()\n'
          'print("READY",flush=True)\n'
          'sys.stdin.readline()\n'
          'db.execute("INSERT INTO restore_probe(id,value) VALUES(?,?)",'
          '("external-after","committed-after-merge"))\n'
          'db.commit()\n'
          'print("DONE",flush=True)\n'
          'db.close()\n';
      final process = await Process.start('python3', [
        '-u',
        '-c',
        worker,
        database.persistenceDatabase.path,
      ]);
      addTearDown(() => process.kill());
      final output = process.stdout
          .transform(const SystemEncoding().decoder)
          .asBroadcastStream();
      await expectLater(output.first, completion(contains('READY')));
      await RawMergeService(
        database,
        backups,
        restores,
      ).restoreMerge(archive, password: 'correct horse battery staple');
      process.stdin.writeln('CONTINUE');
      await process.stdin.flush();
      expect(await process.exitCode, 0);
      final ids = (await database.database.query(
        'restore_probe',
      )).map((row) => row['id']).toSet();
      expect(ids, containsAll(['backup-only', 'external-after']));
    },
  );

  test(
    'Merge interruption rolls back SQL without replacing live DB file',
    () async {
      await setProbe('archived-value');
      final archive = File(path.join(root.path, 'atomic-rollback.butlerly'));
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
      var preserved = false;
      await expectLater(
        RawMergeService(database, backups, restores).restoreMerge(
          archive,
          password: 'correct horse battery staple',
          onStage: (stage) async {
            if (stage == 'original SQLite preserved') {
              preserved = true;
              expect(
                await File(database.persistenceDatabase.path).exists(),
                isTrue,
              );
              throw StateError(
                'injected failure before transactional Merge commit',
              );
            }
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(preserved, isTrue);
      expect(await getProbe(), 'must-stay-live');
      expect(
        await File(
          path.join(databaseDirectory.path, '.raw-restore-journal.json'),
        ).exists(),
        isFalse,
      );
    },
  );

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

    await RawMergeService(
      database,
      backups,
      restores,
    ).restoreMerge(archive, password: 'correct horse battery staple');
    final rows = await database.database.query(
      'restore_probe',
      where: 'id = ?',
      whereArgs: ['deleted-locally'],
    );
    expect(rows, isEmpty);
  });

  test(
    'Replace upgrades prior schema in staging without changing archive',
    () async {
      await setProbe('older-backup-value');
      final oldArchive = await archivedSchema(
        version: 18,
        label: 'older-replace',
      );
      // Historical backups remain previewable, and migration only runs
      // after the user confirms Replace or Merge.
      final inspection = await backups.inspect(
        oldArchive,
        password: 'correct horse battery staple',
      );
      expect(inspection.recordCount, 1);
      final originalArchiveBytes = await oldArchive.readAsBytes();
      await database.database.update(
        'restore_probe',
        {'value': 'live-newer'},
        where: 'id = ?',
        whereArgs: ['original'],
      );

      await restores.restoreReplace(
        oldArchive,
        password: 'correct horse battery staple',
        onStage: (stage) async {
          if (stage == 'database connection close') {
            // Migration occurs before the first live database is closed.
            expect(await getProbe(), 'live-newer');
          }
        },
      );

      expect(await getProbe(), 'older-backup-value');
      final version = await database.database.rawQuery('PRAGMA user_version');
      expect(version.single.values.single, 19);
      final profileTables = await database.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE name = 'financial_profiles'",
      );
      expect(profileTables, hasLength(1));
      expect(await oldArchive.readAsBytes(), originalArchiveBytes);
    },
  );

  test(
    'Merge upgrades prior schema while retaining newer local records',
    () async {
      await setProbe('old-value');
      await database.database.insert('restore_probe', {
        'id': 'backup-only',
        'value': 'import-me',
      });
      final oldArchive = await archivedSchema(
        version: 18,
        label: 'older-merge',
      );
      await database.database.update(
        'restore_probe',
        {'value': 'local-kept'},
        where: 'id = ?',
        whereArgs: ['original'],
      );
      await database.database.delete(
        'restore_probe',
        where: 'id = ?',
        whereArgs: ['backup-only'],
      );

      await RawMergeService(
        database,
        backups,
        restores,
      ).restoreMerge(oldArchive, password: 'correct horse battery staple');
      expect(await getProbe(), 'local-kept');
      final imported = await database.database.query(
        'restore_probe',
        where: 'id = ?',
        whereArgs: ['backup-only'],
      );
      expect(imported.single['value'], 'import-me');
      final version = await database.database.rawQuery('PRAGMA user_version');
      expect(version.single.values.single, 19);
    },
  );

  test('Replace applies consecutive historical schema migrations', () async {
    await setProbe('historical');
    final archive = await archivedSchema(
      version: 17,
      label: 'older-multiple-migrations',
    );
    await database.database.update(
      'restore_probe',
      {'value': 'changed-after-backup'},
      where: 'id = ?',
      whereArgs: ['original'],
    );

    await restores.restoreReplace(
      archive,
      password: 'correct horse battery staple',
    );
    expect(await getProbe(), 'historical');
    expect(
      (await database.database.rawQuery(
        'PRAGMA user_version',
      )).single.values.single,
      19,
    );
    final tables = await database.database.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE name IN ('budgets', 'financial_profiles')",
    );
    expect(tables.map((table) => table['name']).toSet(), {
      'budgets',
      'financial_profiles',
    });
  });

  test('newer unsupported schema rejects without mutating live data', () async {
    await setProbe('never-change-live');
    final archive = await archivedSchema(version: 20, label: 'future-schema');
    final originalArchiveBytes = await archive.readAsBytes();

    // The user sees an update-required prompt during the read-only preview,
    // before any Replace or Merge confirmation and before activation.
    await expectLater(
      backups.inspect(archive, password: 'correct horse battery staple'),
      throwsA(
        isA<NewerBackupSchemaException>()
            .having((error) => error.backupVersion, 'backupVersion', 20)
            .having((error) => error.supportedVersion, 'supportedVersion', 19),
      ),
    );
    await expectLater(
      restores.restoreReplace(
        archive,
        password: 'correct horse battery staple',
      ),
      throwsA(isA<NewerBackupSchemaException>()),
    );
    expect(await getProbe(), 'never-change-live');
    final version = await database.database.rawQuery('PRAGMA user_version');
    expect(version.single.values.single, 19);
    expect(await archive.readAsBytes(), originalArchiveBytes);
  });

  test(
    'staging storage failure does not move original SQLite or evidence',
    () async {
      await setProbe('archived-value');
      final receipt = File(path.join(evidence.path, 'keep-local.bin'));
      await receipt.writeAsBytes([1, 2, 3]);
      final archive = File(path.join(root.path, 'storage-failure.butlerly'));
      await backups.createBackup(
        archive,
        password: 'correct horse battery staple',
      );
      await database.database.update(
        'restore_probe',
        {'value': 'live-after-backup'},
        where: 'id = ?',
        whereArgs: ['original'],
      );
      await receipt.writeAsBytes([9, 8, 7]);

      await expectLater(
        restores.restoreReplace(
          archive,
          password: 'correct horse battery staple',
          onStage: (stage) async {
            if (stage == 'attachment staging') {
              throw const FileSystemException(
                'Not enough space to stage evidence',
                '',
                OSError('No space left on device', 28),
              );
            }
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await getProbe(), 'live-after-backup');
      expect(await receipt.readAsBytes(), [9, 8, 7]);
      expect(
        await File(
          path.join(databaseDirectory.path, '.raw-restore-journal.json'),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'uncertain physical rollback locks the workspace until restart recovery',
    () async {
      await setProbe('archived');
      final archive = File(path.join(root.path, 'rollback-gate.butlerly'));
      await backups.createBackup(
        archive,
        password: 'correct horse battery staple',
      );
      await database.database.update(
        'restore_probe',
        {'value': 'original-must-survive'},
        where: 'id = ?',
        whereArgs: ['original'],
      );
      final data = LocalDataManager(database, localEvidenceDirectory: evidence);
      final manager = LocalBackupManager(database, data);
      final journal = File(
        path.join(databaseDirectory.path, '.raw-restore-journal.json'),
      );
      String? validJournal;
      var failRecoveryCloseOnce = true;
      var connectionConfirmedClosed = false;
      final gateway = LocalWorkspaceDataGateway(
        manager,
        data,
        restoreDiagnosticStage: (stage) async {
          if (stage == 'recovery connection close' && failRecoveryCloseOnce) {
            failRecoveryCloseOnce = false;
            throw StateError('injected SQLite close failure');
          }
          if (stage == 'recovery connection closed') {
            connectionConfirmedClosed = true;
            expect(
              () => database.persistenceDatabase.connection,
              throwsA(isA<Exception>()),
            );
          }
          if (stage == 'replacement files activated') {
            validJournal = await journal.readAsString();
            await journal.writeAsString(
              '{invalid journal for injected recovery failure',
              flush: true,
            );
            throw StateError('force rollback while journal is corrupt');
          }
        },
      );
      await expectLater(
        gateway.restore(
          archive.path,
          mode: LocalRestoreMode.replace,
          password: 'correct horse battery staple',
          postActivationRefresh: () async {},
        ),
        throwsA(isA<RestoreRecoveryRequiredException>()),
      );
      expect(manager.recoveryState.isRecoveryRequired, isTrue);
      expect(await journal.exists(), isTrue);
      expect(
        () => database.persistenceDatabase.connection,
        throwsA(isA<Exception>()),
      );

      // A user-facing recovery retry can finish rollback after the transient
      // journal failure is corrected; it must not use the old restore engine.
      expect(validJournal, isNotNull);
      await journal.writeAsString(validJournal!, flush: true);
      await expectLater(
        gateway.recoverControlledState(postActivationRefresh: () async {}),
        throwsA(isA<StateError>()),
      );
      expect(manager.recoveryState.isRecoveryRequired, isTrue);
      expect(await journal.exists(), isTrue);
      expect(
        () => database.persistenceDatabase.connection,
        throwsA(isA<Exception>()),
      );
      await gateway.recoverControlledState(postActivationRefresh: () async {});
      expect(connectionConfirmedClosed, isTrue);
      expect(await getProbe(), 'original-must-survive');
      expect(manager.recoveryState.isRecoveryRequired, isFalse);
      expect(await journal.exists(), isFalse);

      // Simulate a fresh process to confirm recovery remained durable.
      await database.close();
      await database.initialize();
      expect(await getProbe(), 'original-must-survive');
    },
  );

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
