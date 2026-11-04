import 'dart:io';

import 'package:butlerly/core/data/backup_destination_writer.dart';
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

  test('publication failure identifies stage without reporting success', () async {
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
    expect(await database.database.rawQuery('PRAGMA integrity_check'), [
      {'integrity_check': 'ok'},
    ]);
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
