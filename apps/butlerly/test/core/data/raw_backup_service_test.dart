import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_gateway.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/raw_backup_archive.dart';
import 'package:butlerly/core/data/raw_backup_service.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart'
    show BackupCreationException, BackupCreationStage;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory root;
  late Directory storage;
  late Directory output;
  late Directory evidence;
  late LocalDatabase database;
  late RawBackupService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('butlerly-raw-backup-');
    storage = Directory(path.join(root.path, 'database'))
      ..createSync(recursive: true);
    output = Directory(path.join(root.path, 'external'))
      ..createSync(recursive: true);
    evidence = Directory(path.join(root.path, 'evidence'))
      ..createSync(recursive: true);

    database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: storage.path,
    );
    await database.initialize();
    service = RawBackupService(
      database,
      LocalDataManager(database, localEvidenceDirectory: evidence),
    );
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'creates an encrypted copy of actual SQLite data without changing source',
    () async {
      final before = await database.database.rawQuery(
        'SELECT COUNT(*) AS total FROM sqlite_master',
      );
      final destination = File(path.join(output.path, 'butlerly.butlerly'));
      final result = await service.createBackup(
        destination,
        password: 'correct horse battery staple',
      );
      expect(result.sqliteBytes, greaterThan(0));
      expect(await destination.exists(), isTrue);
      expect(
        await service.inspect(
          destination,
          password: 'correct horse battery staple',
        ),
        isA<RawBackupInspection>(),
      );
      expect(
        await database.database.rawQuery(
          'SELECT COUNT(*) AS total FROM sqlite_master',
        ),
        before,
      );

      final staging = Directory(path.join(root.path, 'restore-staging'));
      await service.prepareRestore(
        destination,
        password: 'correct horse battery staple',
        stagingDirectory: staging,
      );
      final reopened = await databaseFactoryFfi.openDatabase(
        path.join(staging.path, 'butlerly.db'),
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        final count = await reopened.rawQuery(
          'SELECT COUNT(*) AS total FROM sqlite_master',
        );
        expect(count, before);
      } finally {
        await reopened.close();
      }
    },
  );

  test(
    'publication failure identifies stage without reporting success',
    () async {
      final destination = File(path.join(output.path, 'unpublished.butlerly'));
      final failing = RawBackupService(
        database,
        LocalDataManager(database, localEvidenceDirectory: evidence),
        destinationWriter: const _RejectingDestinationWriter(),
      );

      await expectLater(
        failing.createBackup(
          destination,
          password: 'correct horse battery staple',
        ),
        throwsA(
          isA<BackupCreationException>()
              .having(
                (error) => error.stage,
                'stage',
                BackupCreationStage.publication,
              )
              .having(
                (error) => error.cause,
                'cause',
                isA<FileSystemException>(),
              ),
        ),
      );
      expect(await destination.exists(), isFalse);
      final integrity = await database.database.rawQuery(
        'PRAGMA integrity_check',
      );
      expect(integrity.single.values.single, 'ok');
    },
  );

  test(
    'published backup reports missing referenced evidence to the gateway',
    () async {
      final data = LocalDataManager(database, localEvidenceDirectory: evidence);
      await database.database.insert('provenances', {
        'id': 'missing-original-provenance',
        'source_type': 'userEntry',
        'captured_at': DateTime.utc(2026, 11, 4).toIso8601String(),
      });
      await database.database.insert('evidence_items', {
        'id': 'missing-original-receipt',
        'type': 'receipt',
        'original_name': 'missing.pdf',
        'media_type': 'application/pdf',
        'provenance_id': 'missing-original-provenance',
        'created_at': DateTime.utc(2026, 11, 4).toIso8601String(),
        'local_file_name': 'missing.pdf',
      });
      final gateway = LocalWorkspaceDataGateway(
        LocalBackupManager(database, data),
        data,
      );
      final destination = File(
        path.join(output.path, 'missing-evidence.butlerly'),
      );
      final result = await gateway.createPortableBackup(
        destination.path,
        password: 'correct horse battery staple',
      );
      expect(result.attachmentCount, 0);
      expect(result.missingAttachmentCount, 1);
      expect(result.hasMissingAttachments, isTrue);
      expect(await destination.exists(), isTrue);
      final inspection = await service.inspect(
        destination,
        password: 'correct horse battery staple',
      );
      expect(inspection.missingAttachmentCount, 1);
    },
  );

  test(
    'startup removes abandoned raw work and verified prior copies',
    () async {
      const id = '1700000000000000';
      final data = LocalDataManager(database, localEvidenceDirectory: evidence);
      final manager = LocalBackupManager(database, data);
      final backupWork = Directory(
        path.join(storage.path, '.raw-backup-work-$id'),
      )..createSync();
      final readWork = Directory(
        path.join(storage.path, '.raw-backup-read-$id'),
      )..createSync();
      final restoreWork = Directory(
        path.join(storage.path, '.raw-restore-work-$id'),
      )..createSync();
      for (final directory in [backupWork, readWork, restoreWork]) {
        await File(
          path.join(directory.path, 'payload'),
        ).writeAsBytes([1, 2, 3]);
      }
      final previousDb = File(
        path.join(storage.path, 'butlerly.db.raw-restore-previous-$id'),
      );
      final escaped = previousDb.path.replaceAll("'", "''");
      await database.database.execute("VACUUM INTO '$escaped'");
      final previousEvidence = Directory(
        path.join(evidence.parent.path, 'evidence.raw-restore-previous-$id'),
      )..createSync();
      await File(
        path.join(previousEvidence.path, 'old-receipt'),
      ).writeAsBytes([4, 5, 6]);
      final incomingEvidence = Directory(
        path.join(evidence.parent.path, 'evidence.raw-restore-incoming-$id'),
      )..createSync();
      await File(
        path.join(incomingEvidence.path, 'staged-receipt'),
      ).writeAsBytes([7, 8, 9]);
      // This may be the sole recovery source for interrupted publication.
      final encryptedCandidate = File(
        path.join(storage.path, '.raw-backup-$id.butlerly'),
      );
      await encryptedCandidate.writeAsBytes([11, 12]);
      final arbitrary = File(path.join(storage.path, 'my-important.db'));
      await arbitrary.writeAsBytes([13, 14]);

      await manager.cleanupOrphanedPrivateArtifacts();

      expect(await backupWork.exists(), isFalse);
      expect(await readWork.exists(), isFalse);
      expect(await restoreWork.exists(), isFalse);
      expect(await previousDb.exists(), isFalse);
      expect(await previousEvidence.exists(), isFalse);
      expect(await incomingEvidence.exists(), isFalse);
      expect(await encryptedCandidate.readAsBytes(), [11, 12]);
      expect(await arbitrary.readAsBytes(), [13, 14]);
      expect(
        (await database.database.rawQuery(
          'PRAGMA integrity_check',
        )).single.values.single,
        'ok',
      );
    },
  );

  test(
    'torn raw restore journal protects rollback and staging files',
    () async {
      const id = '1700000000000001';
      final data = LocalDataManager(database, localEvidenceDirectory: evidence);
      final manager = LocalBackupManager(database, data);
      final backupWork = Directory(
        path.join(storage.path, '.raw-backup-work-$id'),
      )..createSync();
      final restoreWork = Directory(
        path.join(storage.path, '.raw-restore-work-$id'),
      )..createSync();
      final previousDb = File(
        path.join(storage.path, 'butlerly.db.raw-restore-previous-$id'),
      );
      await previousDb.writeAsBytes([1, 3, 5]);
      final incomingEvidence = Directory(
        path.join(evidence.parent.path, 'evidence.raw-restore-incoming-$id'),
      )..createSync();
      final previousEvidence = Directory(
        path.join(evidence.parent.path, 'evidence.raw-restore-previous-$id'),
      )..createSync();
      final tornJournal = File(
        path.join(storage.path, '.raw-restore-journal.json.tmp'),
      );
      await tornJournal.writeAsString('{partial', flush: true);

      await manager.cleanupOrphanedPrivateArtifacts();

      expect(await backupWork.exists(), isFalse);
      expect(await restoreWork.exists(), isTrue);
      expect(await previousDb.readAsBytes(), [1, 3, 5]);
      expect(await previousEvidence.exists(), isTrue);
      expect(await incomingEvidence.exists(), isTrue);
      expect(await tornJournal.readAsString(), '{partial');
    },
  );

  test(
    'old rollback copies survive until live referenced evidence validates',
    () async {
      const id = '1700000000000002';
      final data = LocalDataManager(database, localEvidenceDirectory: evidence);
      final manager = LocalBackupManager(database, data);
      await database.database.insert('provenances', {
        'id': 'cleanup-evidence-provenance',
        'source_type': 'userEntry',
        'captured_at': DateTime.utc(2026, 11, 5).toIso8601String(),
      });
      await database.database.insert('evidence_items', {
        'id': 'cleanup-evidence',
        'type': 'receipt',
        'original_name': 'receipt.pdf',
        'media_type': 'application/pdf',
        'provenance_id': 'cleanup-evidence-provenance',
        'created_at': DateTime.utc(2026, 11, 5).toIso8601String(),
        'local_file_name': 'receipt.pdf',
      });
      final previousDb = File(
        path.join(storage.path, 'butlerly.db.raw-restore-previous-$id'),
      );
      await previousDb.writeAsBytes([9, 9]);
      final previousEvidence = Directory(
        path.join(evidence.parent.path, 'evidence.raw-restore-previous-$id'),
      )..createSync();
      await File(
        path.join(previousEvidence.path, 'receipt.pdf'),
      ).writeAsBytes([7, 7, 7]);

      await manager.cleanupOrphanedPrivateArtifacts();
      expect(await previousDb.exists(), isTrue);
      expect(await previousEvidence.exists(), isTrue);

      // Only after the live evidence is restored can the old copies go.
      await File(
        path.join(evidence.path, 'receipt.pdf'),
      ).writeAsBytes([7, 7, 7]);
      await manager.cleanupOrphanedPrivateArtifacts();
      expect(await previousDb.exists(), isFalse);
      expect(await previousEvidence.exists(), isFalse);
    },
  );

  test('active recovery marker prevents all raw staging cleanup', () async {
    const id = '1700000000000003';
    final data = LocalDataManager(database, localEvidenceDirectory: evidence);
    final manager = LocalBackupManager(database, data);
    final work = Directory(path.join(storage.path, '.raw-backup-read-$id'))
      ..createSync();
    await manager.recoveryState.markUnknownRequired(
      operationId: 'recovery-$id',
      reason: 'raw-restore-rollback-incomplete',
    );

    await manager.cleanupOrphanedPrivateArtifacts();

    expect(await work.exists(), isTrue);
    expect(manager.recoveryState.isRecoveryRequired, isTrue);
  });

  test('incorrect password cannot produce staged files', () async {
    final destination = File(path.join(output.path, 'butlerly.butlerly'));
    await service.createBackup(
      destination,
      password: 'correct horse battery staple',
    );
    final staging = Directory(path.join(root.path, 'wrong-password-staging'));
    await expectLater(
      service.prepareRestore(
        destination,
        password: 'wrong password',
        stagingDirectory: staging,
      ),
      throwsA(isA<Exception>()),
    );
    expect(await staging.exists(), isFalse);
  });
}

final class _RejectingDestinationWriter implements BackupDestinationWriter {
  const _RejectingDestinationWriter();

  @override
  Future<void> publish({
    required File source,
    required File destination,
    required Directory privateDirectory,
    required String operationId,
  }) async {
    throw const FileSystemException('Destination is not writable.');
  }
}
