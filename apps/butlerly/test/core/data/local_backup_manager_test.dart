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

  test('merge keeps newer local rows and restores older backup rows', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final oldTime = DateTime.utc(2026, 1, 1);

    await fixture.insertTransaction(
      id: 'keep-local',
      description: 'Backup value',
      updatedAt: oldTime,
    );
    await fixture.insertTransaction(
      id: 'restore-backup',
      description: 'Backup wins',
      updatedAt: oldTime,
    );
    final backup = File(path.join(fixture.root.path, 'merge.butlerlybackup'));
    await fixture.backups.createBackup(backup);

    final future = DateTime.now().toUtc().add(const Duration(minutes: 5));
    await fixture.database.database.update(
      'transactions',
      {'description': 'New local value', 'updated_at': future.toIso8601String()},
      where: 'id = ?',
      whereArgs: ['keep-local'],
    );
    await fixture.database.database.update(
      'transactions',
      {'description': 'Stale local value', 'updated_at': oldTime.toIso8601String()},
      where: 'id = ?',
      whereArgs: ['restore-backup'],
    );
    await fixture.insertTransaction(
      id: 'new-local',
      description: 'Created after backup',
      updatedAt: future,
    );

    final result = await fixture.backups.restore(
      backup,
      mode: LocalRestoreMode.merge,
    );

    expect(result.keptNewerLocalRows, greaterThanOrEqualTo(1));
    expect(await fixture.description('keep-local'), 'New local value');
    expect(await fixture.description('restore-backup'), 'Backup wins');
    expect(await fixture.description('new-local'), 'Created after backup');
  });

  test('merge applies backup deletion tombstone unless local row is newer', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final oldTime = DateTime.utc(2026, 1, 1);

    await fixture.insertTransaction(
      id: 'deleted-at-source',
      description: 'Will be deleted',
      updatedAt: oldTime,
    );
    await fixture.database.database.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: ['deleted-at-source'],
    );
    final backup = File(path.join(fixture.root.path, 'deleted.butlerlybackup'));
    await fixture.backups.createBackup(backup);

    await fixture.insertTransaction(
      id: 'deleted-at-source',
      description: 'Old local copy',
      updatedAt: oldTime,
    );
    await fixture.backups.restore(backup, mode: LocalRestoreMode.merge);
    expect(await fixture.description('deleted-at-source'), isNull);
  });

  test('backup restores checksum-protected evidence in merge mode', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final evidence = File(path.join(fixture.evidence.path, 'receipt.bin'));
    await evidence.writeAsBytes([1, 2, 3, 4]);
    final backup = File(path.join(fixture.root.path, 'evidence.butlerlybackup'));
    await fixture.backups.createBackup(backup);
    await evidence.delete();

    await fixture.backups.restore(backup, mode: LocalRestoreMode.merge);

    expect(await evidence.readAsBytes(), [1, 2, 3, 4]);
  });
}

final class _Fixture {
  _Fixture({
    required this.root,
    required this.evidence,
    required this.database,
    required this.backups,
  });

  final Directory root;
  final Directory evidence;
  final LocalDatabase database;
  final LocalBackupManager backups;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('butlerly-backup-test-');
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
      root: root,
      evidence: evidence,
      database: database,
      backups: LocalBackupManager(database, data),
    );
  }

  Future<void> dispose() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<void> insertTransaction({
    required String id,
    required String description,
    required DateTime updatedAt,
  }) async {
    await database.database.insert('transactions', {
      'id': id,
      'unknown_time_reason': 'unknown',
      'amount_coefficient': '1234',
      'amount_scale': 2,
      'currency': 'USD',
      'direction': 'expense',
      'source_type': 'manual',
      'status': 'active',
      'description': description,
      'created_at': updatedAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    });
  }

  Future<String?> description(String id) async {
    final rows = await database.database.query(
      'transactions',
      columns: ['description'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['description'] as String?;
  }
}
