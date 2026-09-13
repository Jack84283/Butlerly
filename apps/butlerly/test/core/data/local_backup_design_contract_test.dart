import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('Merge preserves a pre-restore safety package', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2026, 1, 1);
    await fixture.insertTransaction('existing', old, amount: '100');
    final backup = File(path.join(fixture.root.path, 'merge-source.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    final newer = DateTime.now().toUtc().add(const Duration(minutes: 1));
    await fixture.insertTransaction('newer-local', newer, amount: '250');

    final result = await fixture.manager.restore(
      backup,
      mode: LocalRestoreMode.merge,
    );

    expect(result.mode, LocalRestoreMode.merge);
    expect(
      await fixture.database.database.query(
        'transactions',
        where: 'id = ?',
        whereArgs: ['newer-local'],
      ),
      hasLength(1),
    );
    final safetyDirectory = Directory(
      path.join(fixture.root.path, '.butlerly-recovery', 'safety-backups'),
    );
    final safetyFiles = await safetyDirectory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    expect(
      safetyFiles.any(
        (file) => path.basename(file.path).startsWith('Before Merge '),
      ),
      isTrue,
    );
    expect(
      Directory(
        path.join(fixture.documents.path, 'Butlerly Safety Backups'),
      ).existsSync(),
      isFalse,
    );
  });

  test('refresh failure preserves activated state and retries in recovery', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final timestamp = DateTime.utc(2026, 1, 1);
    await fixture.insertTransaction('tx-1', timestamp, amount: '100');
    final backup = File(path.join(fixture.root.path, 'replace-source.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    await fixture.database.database.update(
      'transactions',
      {
        'amount_coefficient': '200',
        'updated_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 1))
            .toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: ['tx-1'],
    );

    var refreshCalls = 0;
    await expectLater(
      fixture.manager.restore(
        backup,
        mode: LocalRestoreMode.replace,
        postActivationRefresh: () async {
          refreshCalls++;
          throw StateError('synthetic refresh failure');
        },
      ),
      throwsA(isA<RestoreRecoveryRequiredException>()),
    );

    final activated = await fixture.database.database.query(
      'transactions',
      where: 'id = ?',
      whereArgs: ['tx-1'],
    );
    expect(activated, hasLength(1));
    expect(activated.single['amount_coefficient'], '100');
    expect(refreshCalls, 1);
    expect(fixture.manager.recoveryState.isRecoveryRequired, isTrue);
    expect(fixture.manager.recoveryState.incident?.retryCurrentState, isTrue);
    expect(
      fixture.manager.recoveryState.incident?.reason,
      'post-activation-validation-or-refresh-failed',
    );
    expect(
      fixture.manager.recoveryState.incident?.safetyBackupPath,
      isNotEmpty,
    );

    await fixture.manager.recoverControlledState(
      postActivationRefresh: () async => refreshCalls++,
    );

    expect(refreshCalls, 2);
    expect(fixture.manager.recoveryState.isRecoveryRequired, isFalse);
    final recovered = await fixture.database.database.query(
      'transactions',
      where: 'id = ?',
      whereArgs: ['tx-1'],
    );
    expect(recovered.single['amount_coefficient'], '100');
  });

  test('Merge preserves an edit made after staging snapshot', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2026, 1, 1);
    await fixture.insertTransaction('tx-concurrent', old, amount: '100');
    final backup = File(path.join(fixture.root.path, 'concurrent.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    final slowEvidence = File(path.join(fixture.evidence.path, 'slow-stage.bin'));
    await slowEvidence.writeAsBytes(
      List<int>.filled(24 * 1024 * 1024, 7),
      flush: true,
    );

    final restoreFuture = fixture.manager.restore(
      backup,
      mode: LocalRestoreMode.merge,
    );
    final stageEvidence = await _waitForStagingEvidence(fixture.root);
    expect(stageEvidence, isNotNull);

    await fixture.database.database.update(
      'transactions',
      {
        'amount_coefficient': '300',
        'updated_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: ['tx-concurrent'],
    );

    await restoreFuture;
    final rows = await fixture.database.database.query(
      'transactions',
      columns: ['amount_coefficient'],
      where: 'id = ?',
      whereArgs: ['tx-concurrent'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['amount_coefficient'], '300');
  });

  test('isolated restore staging is removed after successful activation', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final timestamp = DateTime.utc(2026, 1, 1);
    await fixture.insertTransaction('tx-stage', timestamp, amount: '100');
    final backup = File(path.join(fixture.root.path, 'stage-source.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

    final stageDirectories = await fixture.root
        .list()
        .where(
          (entity) =>
              entity is Directory &&
              path.basename(entity.path).startsWith('.butlerly-restore-stage-'),
        )
        .toList();
    expect(stageDirectories, isEmpty);
  });

  test('successful restores retain at most two safety snapshots', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final timestamp = DateTime.utc(2026, 1, 1);
    await fixture.insertTransaction('tx-retention', timestamp, amount: '100');
    final backup = File(path.join(fixture.root.path, 'retention.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    for (var index = 0; index < 4; index++) {
      await fixture.database.database.update(
        'transactions',
        {'description': 'local-$index'},
        where: 'id = ?',
        whereArgs: ['tx-retention'],
      );
      await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);
    }

    final safetyDirectory = Directory(
      path.join(fixture.root.path, '.butlerly-recovery', 'safety-backups'),
    );
    final files = await safetyDirectory
        .list(followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.butlerlybackup'))
        .toList();
    expect(files.length, lessThanOrEqualTo(2));
  });
}

Future<Directory?> _waitForStagingEvidence(Directory root) async {
  for (var attempt = 0; attempt < 5000; attempt++) {
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          !path.basename(entity.path).startsWith('.butlerly-restore-stage-')) {
        continue;
      }
      final evidence = Directory(path.join(entity.path, 'evidence'));
      if (await evidence.exists()) return evidence;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  return null;
}

final class _Fixture {
  _Fixture(
    this.root,
    this.documents,
    this.evidence,
    this.database,
    this.manager,
  );

  final Directory root;
  final Directory documents;
  final Directory evidence;
  final LocalDatabase database;
  final LocalBackupManager manager;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-backup-design-contract-',
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
    return _Fixture(
      root,
      documents,
      evidence,
      database,
      LocalBackupManager(database, data),
    );
  }

  Future<void> insertTransaction(
    String id,
    DateTime timestamp, {
    required String amount,
  }) async {
    await database.database.insert('transactions', {
      'id': id,
      'unknown_time_reason': 'unknown',
      'amount_coefficient': amount,
      'amount_scale': 2,
      'currency': 'USD',
      'direction': 'expense',
      'source_type': 'manual',
      'status': 'active',
      'created_at': timestamp.toIso8601String(),
      'updated_at': timestamp.toIso8601String(),
    });
  }

  Future<void> dispose() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
