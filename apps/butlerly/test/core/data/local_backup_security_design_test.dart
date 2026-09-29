import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:butlerly/core/data/backup_encryption.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/restore_recovery_state.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test(
    'portable backup is encrypted and requires the correct password',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('encrypted-source');
      final backup = File(
        path.join(fixture.root.path, 'portable.butlerlybackup'),
      );

      await fixture.manager.createPortableBackup(
        backup,
        password: 'correct horse battery staple',
      );

      expect(await fixture.manager.isEncryptedBackup(backup), isTrue);
      final prefix = await backup
          .openRead(0, 15)
          .fold<List<int>>(<int>[], (value, chunk) => value..addAll(chunk));
      expect(
        utf8.decode(prefix, allowMalformed: true),
        isNot(contains('BUTLERLYBACKUP2')),
      );

      await expectLater(
        fixture.manager.inspect(backup),
        throwsA(isA<BackupPasswordRequiredException>()),
      );
      await expectLater(
        fixture.manager.inspect(backup, password: 'incorrect password'),
        throwsA(isA<BackupPasswordOrIntegrityException>()),
      );

      final inspection = await fixture.manager.inspect(
        backup,
        password: 'correct horse battery staple',
      );
      expect(inspection.recordCount, greaterThan(0));
    },
  );

  test(
    'portable backup publishes through the selected file without external siblings',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final selectedDirectory = await Directory.systemTemp.createTemp(
        'butlerly-selected-backup-',
      );
      addTearDown(() => selectedDirectory.delete(recursive: true));
      await fixture.insertTransaction('selected-destination');
      final destination = File(
        path.join(selectedDirectory.path, 'portable.butlerlybackup'),
      );

      await fixture.manager.createPortableBackup(
        destination,
        password: 'correct horse battery staple',
      );

      expect(await destination.exists(), isTrue);
      expect(
        await fixture.manager.inspect(
          destination,
          password: 'correct horse battery staple',
        ),
        isA<BackupInspection>(),
      );
      expect(
        await _namesStarting(selectedDirectory, 'portable.butlerlybackup.'),
        isEmpty,
      );
      expect(await _namesStarting(fixture.root, '.portable-backup-'), isEmpty);
    },
  );

  test(
    'portable backup replacement does not scan or write beside destination',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final selectedDirectory = await Directory.systemTemp.createTemp(
        'butlerly-selected-backup-replace-',
      );
      addTearDown(() => selectedDirectory.delete(recursive: true));
      final destination = File(
        path.join(selectedDirectory.path, 'portable.butlerlybackup'),
      );
      const password = 'correct horse battery staple';

      await fixture.insertTransaction('before-replacement');
      await fixture.manager.createPortableBackup(
        destination,
        password: password,
      );
      await fixture.insertTransaction('after-replacement');
      await fixture.manager.createPortableBackup(
        destination,
        password: password,
      );

      final inspection = await fixture.manager.inspect(
        destination,
        password: password,
      );
      expect(inspection.recordCount, greaterThan(1));
      expect(
        await _namesStarting(selectedDirectory, 'portable.butlerlybackup.'),
        isEmpty,
      );
      expect(await _namesStarting(fixture.root, '.portable-backup-'), isEmpty);
    },
  );

  test(
    'portable backup publication failure cleans private artifacts',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final selectedDirectory = await Directory.systemTemp.createTemp(
        'butlerly-selected-backup-failure-',
      );
      addTearDown(() => selectedDirectory.delete(recursive: true));
      final destination = File(
        path.join(selectedDirectory.path, 'portable.butlerlybackup'),
      )..writeAsStringSync('existing selected backup');
      final manager = LocalBackupManager(
        fixture.database,
        fixture.data,
        recoveryState: fixture.manager.recoveryState,
        destinationWriter: const _FailingDestinationWriter(),
      );

      await expectLater(
        manager.createPortableBackup(
          destination,
          password: 'correct horse battery staple',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await destination.readAsString(), 'existing selected backup');
      expect(
        await _namesStarting(selectedDirectory, 'portable.butlerlybackup.'),
        isEmpty,
      );
      expect(await _namesStarting(fixture.root, '.portable-backup-'), isEmpty);
    },
  );

  test('restore accepts supported KDF parameters recorded in header', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.insertTransaction('kdf-evolution');
    final inner = File(path.join(fixture.root.path, 'inner.butlerlybackup'));
    final encrypted = File(
      path.join(fixture.root.path, 'encrypted.butlerlybackup'),
    );
    final modified = File(
      path.join(fixture.root.path, 'modified.butlerlybackup'),
    );
    final output = File(
      path.join(fixture.root.path, 'modified-clear.butlerlybackup'),
    );
    const password = 'correct horse battery staple';
    const encryption = BackupEncryption();

    await fixture.manager.createBackup(inner);
    await encryption.encrypt(inner, encrypted, password: password);

    final bytes = await encrypted.readAsBytes();
    final magicLength = BackupEncryption.magic.length;
    final headerLength = _decodeInt64(
      bytes.sublist(magicLength, magicLength + 8),
    );
    final headerStart = magicLength + 8;
    final headerEnd = headerStart + headerLength;
    final header =
        (jsonDecode(utf8.decode(bytes.sublist(headerStart, headerEnd))) as Map)
            .cast<String, Object?>();
    header['kdfIterations'] = 3;
    final headerBytes = utf8.encode(jsonEncode(header));
    final rebuilt = BytesBuilder(copy: false)
      ..add(BackupEncryption.magic)
      ..add(_encodeInt64(headerBytes.length))
      ..add(headerBytes)
      ..add(bytes.sublist(headerEnd));
    await modified.writeAsBytes(rebuilt.takeBytes(), flush: true);

    await expectLater(
      encryption.decrypt(modified, output, password: password),
      throwsA(isA<BackupPasswordOrIntegrityException>()),
    );
  });

  test('backup creation shares the evidence mutation boundary', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final backup = File(
      path.join(fixture.root.path, 'coherent.butlerlybackup'),
    );
    final entered = Completer<void>();
    final release = Completer<void>();

    final heldMutation = EvidenceMutationLock.runExclusive(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;

    final backupFuture = fixture.manager.createBackup(backup);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await backup.exists(), isFalse);

    release.complete();
    await heldMutation;
    await backupFuture;
    expect(await backup.exists(), isTrue);
  });

  test(
    'controlled recovery requirement persists across restart state',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final safety = File(
        path.join(fixture.root.path, 'safety.butlerlybackup'),
      );
      await fixture.manager.createBackup(safety);

      await fixture.manager.recoveryState.markRequired(
        operationId: 'restore-test',
        safetyBackup: safety,
        reason: 'post-activation-validation-or-refresh-failed',
        retryCurrentState: true,
      );

      final reloaded = RestoreRecoveryState(fixture.data);
      await reloaded.initialize();
      expect(reloaded.isRecoveryRequired, isTrue);
      expect(reloaded.incident?.operationId, 'restore-test');
      expect(reloaded.incident?.safetyBackupPath, safety.path);
      expect(reloaded.incident?.retryCurrentState, isTrue);

      await reloaded.clear();
      final afterClear = RestoreRecoveryState(fixture.data);
      await afterClear.initialize();
      expect(afterClear.isRecoveryRequired, isFalse);
    },
  );

  test('syntactically valid malformed recovery marker fails closed', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final evidence = await fixture.data.evidenceDirectory();
    final marker = File('${evidence.path}.restore-recovery-required.json');
    await marker.writeAsString('{}', flush: true);

    final reloaded = RestoreRecoveryState(fixture.data);
    await reloaded.initialize();

    expect(reloaded.isRecoveryRequired, isTrue);
    expect(reloaded.incident?.reason, 'recovery-marker-unreadable');
    expect(await marker.exists(), isTrue);
  });

  test('interrupted recovery marker replacement fails closed', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final evidence = await fixture.data.evidenceDirectory();
    final marker = File('${evidence.path}.restore-recovery-required.json');
    final temporary = File('${marker.path}.tmp');
    await temporary.writeAsString(
      '{"operationId":"restore-temp","safetyBackupPath":"",'
      '"reason":"activation-rollback-failed"}',
      flush: true,
    );

    final reloaded = RestoreRecoveryState(fixture.data);
    await reloaded.initialize();

    expect(reloaded.isRecoveryRequired, isTrue);
    expect(reloaded.incident?.reason, 'recovery-marker-interrupted');
    expect(await temporary.exists(), isTrue);
  });

  test('new marker temp prevents trusting an older main marker', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final oldSafety = File(
      path.join(fixture.root.path, 'old-safety.butlerlybackup'),
    );
    await fixture.manager.createBackup(oldSafety);
    await fixture.manager.recoveryState.markRequired(
      operationId: 'old-operation',
      safetyBackup: oldSafety,
      reason: 'old-incident',
    );

    final evidence = await fixture.data.evidenceDirectory();
    final marker = File('${evidence.path}.restore-recovery-required.json');
    final temporary = File('${marker.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'operationId': 'new-operation',
        'safetyBackupPath': '',
        'reason': 'new-incident',
        'retryCurrentState': false,
      }),
      flush: true,
    );

    final reloaded = RestoreRecoveryState(fixture.data);
    await reloaded.initialize();

    expect(reloaded.incident?.reason, 'recovery-marker-interrupted');
    expect(reloaded.incident?.operationId, 'unknown');
    expect(reloaded.incident?.safetyBackupPath, isEmpty);
    expect(await marker.exists(), isTrue);
    expect(await temporary.exists(), isTrue);
  });

  test(
    'startup cleanup removes private plaintext artifacts but keeps safety data',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final decrypted = File(
        path.join(fixture.root.path, '.backup-decrypt-orphan.butlerlybackup'),
      );
      final plain = File(
        path.join(fixture.root.path, '.portable-backup-orphan.butlerlybackup'),
      );
      final verify = File(
        path.join(
          fixture.root.path,
          '.portable-backup-verify-orphan.butlerlybackup',
        ),
      );
      final stage = Directory(
        path.join(fixture.root.path, '.butlerly-restore-stage-orphan'),
      );
      await decrypted.writeAsString('plaintext');
      await plain.writeAsString('plaintext');
      await verify.writeAsString('plaintext');
      await stage.create();
      await File(
        path.join(stage.path, 'copy.db'),
      ).writeAsString('private-copy');

      final safetyDirectory = await fixture.data.safetyBackupDirectory();
      final safety = File(
        path.join(safetyDirectory.path, 'Before Merge keep.butlerlybackup'),
      );
      await safety.writeAsString('safety');

      await fixture.manager.cleanupOrphanedPrivateArtifacts();

      expect(await decrypted.exists(), isFalse);
      expect(await plain.exists(), isFalse);
      expect(await verify.exists(), isFalse);
      expect(await stage.exists(), isFalse);
      expect(await safety.exists(), isTrue);
    },
  );

  test(
    'startup cleanup preserves interrupted portable publication recovery data',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final selectedDirectory = await Directory.systemTemp.createTemp(
        'butlerly-selected-backup-recovery-',
      );
      addTearDown(() => selectedDirectory.delete(recursive: true));
      final source = File(
        path.join(fixture.root.path, '.portable-backup-encrypted-interrupted'),
      )..writeAsStringSync('new backup');
      final previous = File(
        path.join(
          fixture.root.path,
          '.portable-backup-previous-interrupted.butlerlybackup',
        ),
      )..writeAsStringSync('existing backup');
      final destination = File(
        path.join(selectedDirectory.path, 'portable.butlerlybackup'),
      )..writeAsStringSync('partial backup');
      final recovery = BackupPublicationRecovery(
        operationId: 'interrupted',
        sourcePath: source.path,
        destinationPath: destination.path,
        previousPath: previous.path,
        hadExistingDestination: true,
        previousReady: true,
      );
      const store = FileBackupPublicationRecoveryStore();
      await store.write(fixture.root, recovery);

      await fixture.manager.cleanupOrphanedPrivateArtifacts();

      expect(await source.exists(), isTrue);
      expect(await previous.exists(), isTrue);
      expect(await store.read(fixture.root), hasLength(1));

      await fixture.manager.recoverInterruptedPortableBackupPublications();

      expect(await destination.readAsString(), 'existing backup');
      expect(await previous.exists(), isFalse);
      expect(await store.read(fixture.root), isEmpty);
    },
  );

  test(
    'startup cleanup fails closed when portable recovery metadata is unreadable',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final marker = File(
        path.join(
          fixture.root.path,
          '.portable-backup-recovery-unreadable.json',
        ),
      )..writeAsStringSync('{not-json');
      final source = File(
        path.join(fixture.root.path, '.portable-backup-encrypted-orphan'),
      )..writeAsStringSync('encrypted candidate');
      final previous = File(
        path.join(
          fixture.root.path,
          '.portable-backup-previous-orphan.butlerlybackup',
        ),
      )..writeAsStringSync('previous backup');

      await fixture.manager.cleanupOrphanedPrivateArtifacts();

      expect(await marker.exists(), isTrue);
      expect(await source.exists(), isTrue);
      expect(await previous.exists(), isTrue);
    },
  );

  test(
    'inaccessible destination surfaces recovery state until reauthorized',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final selectedDirectory = Directory(
        path.join(fixture.root.path, 'selected-destination'),
      );
      final destination = File(
        path.join(selectedDirectory.path, 'portable.butlerlybackup'),
      );
      final source = File(
        path.join(fixture.root.path, '.portable-backup-encrypted-recovery'),
      )..writeAsStringSync('new backup');
      final previous = File(
        path.join(
          fixture.root.path,
          '.portable-backup-previous-recovery.butlerlybackup',
        ),
      )..writeAsStringSync('existing backup');
      final recovery = BackupPublicationRecovery(
        operationId: 'recovery',
        sourcePath: source.path,
        destinationPath: destination.path,
        previousPath: previous.path,
        hadExistingDestination: true,
        previousReady: true,
      );
      const store = FileBackupPublicationRecoveryStore();
      await store.write(fixture.root, recovery);

      await expectLater(
        fixture.manager.recoverInterruptedPortableBackupPublications(),
        throwsA(isA<BackupPublicationRecoveryRequiredException>()),
      );
      expect(
        fixture.manager.publicationRecoveryState.isRecoveryRequired,
        isTrue,
      );
      expect(await previous.exists(), isTrue);

      await selectedDirectory.create(recursive: true);
      await fixture.manager.recoverInterruptedPortableBackupPublications(
        authorizedDestinationPath: destination.path,
      );

      expect(
        fixture.manager.publicationRecoveryState.isRecoveryRequired,
        isFalse,
      );
      expect(await destination.readAsString(), 'existing backup');
      expect(await previous.exists(), isFalse);
      expect(await source.exists(), isFalse);
    },
  );

  test(
    'portable backup keeps source artifacts when recovery finalization fails',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('recovery-finalization');
      final destination = File(
        path.join(fixture.root.path, 'portable.butlerlybackup'),
      )..writeAsStringSync('existing backup');
      final store = _FailOnceClearStore();
      final manager = LocalBackupManager(
        fixture.database,
        fixture.data,
        recoveryState: fixture.manager.recoveryState,
        publicationRecoveryStore: store,
      );

      await expectLater(
        manager.createPortableBackup(
          destination,
          password: 'correct horse battery staple',
        ),
        throwsA(isA<BackupPublicationRecoveryRequiredException>()),
      );
      expect(
        await _namesStarting(fixture.root, '.portable-backup-encrypted-'),
        isNotEmpty,
      );
      expect(await store.read(fixture.root), hasLength(1));

      await manager.recoverInterruptedPortableBackupPublications();

      expect(await _namesStarting(fixture.root, '.portable-backup-'), isEmpty);
      expect(await store.read(fixture.root), isEmpty);
      expect(await manager.isEncryptedBackup(destination), isTrue);
    },
  );

  test(
    'unrecoverable incident can reset local data without reopening early',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('reset-source');
      await fixture.manager.recoveryState.markUnknownRequired(
        operationId: 'restore-unrecoverable',
        reason: 'indeterminate-restore-recovery',
      );

      var refreshSawRecoveryGate = false;
      await fixture.manager.resetControlledRecovery(
        postResetRefresh: () async {
          refreshSawRecoveryGate =
              fixture.manager.recoveryState.isRecoveryRequired;
        },
      );

      expect(refreshSawRecoveryGate, isTrue);
      expect(fixture.manager.recoveryState.isRecoveryRequired, isFalse);
      expect(await fixture.database.database.query('transactions'), isEmpty);
    },
  );
}

Uint8List _encodeInt64(int value) {
  final data = ByteData(8)..setUint64(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int _decodeInt64(List<int> bytes) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return data.getUint64(0, Endian.big);
}

final class _Fixture {
  const _Fixture(this.root, this.database, this.data, this.manager);

  final Directory root;
  final LocalDatabase database;
  final LocalDataManager data;
  final LocalBackupManager manager;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-backup-security-design-',
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
    final data = LocalDataManager(
      database,
      documentsDirectory: documents,
      localEvidenceDirectory: evidence,
    );
    final recoveryState = RestoreRecoveryState(data);
    return _Fixture(
      root,
      database,
      data,
      LocalBackupManager(database, data, recoveryState: recoveryState),
    );
  }

  Future<void> insertTransaction(String id) async {
    final timestamp = DateTime.utc(2026, 1, 1).toIso8601String();
    await database.database.insert('transactions', {
      'id': id,
      'unknown_time_reason': 'unknown',
      'amount_coefficient': '1234',
      'amount_scale': 2,
      'currency': 'USD',
      'direction': 'expense',
      'source_type': 'manual',
      'status': 'active',
      'description': 'Encrypted backup test',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
  }

  Future<void> dispose() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<List<String>> _namesStarting(Directory directory, String prefix) async {
  if (!await directory.exists()) return const [];
  final names = <String>[];
  await for (final entity in directory.list(followLinks: false)) {
    final name = path.basename(entity.path);
    if (name.startsWith(prefix)) names.add(name);
  }
  return names;
}

final class _FailingDestinationWriter implements BackupDestinationWriter {
  const _FailingDestinationWriter();

  @override
  Future<void> publish({
    required File source,
    required File destination,
    required Directory privateDirectory,
    required String operationId,
  }) async {
    throw const FileSystemException('simulated destination failure');
  }
}

final class _FailOnceClearStore implements BackupPublicationRecoveryStore {
  _FailOnceClearStore()
    : _delegate = const FileBackupPublicationRecoveryStore();

  final BackupPublicationRecoveryStore _delegate;
  bool _failed = false;

  @override
  Future<void> write(
    Directory privateDirectory,
    BackupPublicationRecovery recovery,
  ) => _delegate.write(privateDirectory, recovery);

  @override
  Future<void> clear(
    Directory privateDirectory,
    BackupPublicationRecovery recovery,
  ) {
    if (!_failed) {
      _failed = true;
      throw const FileSystemException('simulated recovery marker failure');
    }
    return _delegate.clear(privateDirectory, recovery);
  }

  @override
  Future<List<BackupPublicationRecovery>> read(Directory privateDirectory) =>
      _delegate.read(privateDirectory);
}
