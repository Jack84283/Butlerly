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

  test('restore accepts supported KDF parameters recorded in header', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.insertTransaction('kdf-evolution');
    final inner = File(path.join(fixture.root.path, 'inner.butlerlybackup'));
    final encrypted = File(path.join(fixture.root.path, 'encrypted.butlerlybackup'));
    final modified = File(path.join(fixture.root.path, 'modified.butlerlybackup'));
    final output = File(path.join(fixture.root.path, 'modified-clear.butlerlybackup'));
    const password = 'correct horse battery staple';
    const encryption = BackupEncryption();

    await fixture.manager.createBackup(inner);
    await encryption.encrypt(inner, encrypted, password: password);

    final bytes = await encrypted.readAsBytes();
    final magicLength = BackupEncryption.magic.length;
    final headerLength = _decodeInt64(bytes.sublist(magicLength, magicLength + 8));
    final headerStart = magicLength + 8;
    final headerEnd = headerStart + headerLength;
    final header = (jsonDecode(utf8.decode(bytes.sublist(headerStart, headerEnd))) as Map)
        .cast<String, Object?>();
    // A future build may strengthen Argon2 without changing the wrapper format.
    // Altering the authenticated header makes this package fail GCM validation,
    // but it must reach authentication rather than being rejected as an
    // unsupported format solely because the KDF value differs from today's.
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

Uint8List _encodeInt64(int value) {
  final data = ByteData(8)..setUint64(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int _decodeInt64(List<int> bytes) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return data.getUint64(0, Endian.big);
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
