import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  test('portable backup is encrypted and requires the correct password', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.insertTransaction('encrypted-source');
    final backup = File(path.join(fixture.root.path, 'portable.butlerlybackup'));

    await fixture.manager.createPortableBackup(
      backup,
      password: 'correct horse battery staple',
    );

    expect(await fixture.manager.isEncryptedBackup(backup), isTrue);
    final prefix = await backup.openRead(0, 15).fold<List<int>>(
      <int>[],
      (value, chunk) => value..addAll(chunk),
    );
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
  });

  test('backup creation shares the evidence mutation boundary', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final backup = File(path.join(fixture.root.path, 'coherent.butlerlybackup'));
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

  test('controlled recovery requirement persists across restart state', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final safety = File(path.join(fixture.root.path, 'safety.butlerlybackup'));
    await fixture.manager.createBackup(safety);

    await fixture.manager.recoveryState.markRequired(
      operationId: 'restore-test',
      safetyBackup: safety,
      reason: 'activation-rollback-failed',
    );

    final reloaded = RestoreRecoveryState(fixture.data);
    await reloaded.initialize();
    expect(reloaded.isRecoveryRequired, isTrue);
    expect(reloaded.incident?.operationId, 'restore-test');
    expect(reloaded.incident?.safetyBackupPath, safety.path);

    await reloaded.clear();
    final afterClear = RestoreRecoveryState(fixture.data);
    await afterClear.initialize();
    expect(afterClear.isRecoveryRequired, isFalse);
  });

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
}

final class _Fixture {
  const _Fixture(
    this.root,
    this.database,
    this.data,
    this.manager,
  );

  final Directory root;
  final LocalDatabase database;
  final LocalDataManager data;
  final LocalBackupManager manager;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-backup-security-design-',
    );
    final documents = Directory(path.join(root.path, 'documents'))..createSync();
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
      LocalBackupManager(
        database,
        data,
        recoveryState: recoveryState,
      ),
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
