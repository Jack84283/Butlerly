import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart' show sha256Bytes;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('merge restore preserves historical master-data updatedAt', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2025, 1, 1).toIso8601String();
    await fixture.database.database.insert('merchants', {
      'id': 'merchant-user-review',
      'name': 'Review Merchant',
      'status': 'active',
      'normalized_name': 'review merchant',
      'is_built_in': 0,
      'created_at': old,
      'updated_at': old,
    });
    final backup = File(path.join(fixture.root.path, 'timestamps.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);

    final rows = await fixture.database.database.query(
      'merchants',
      columns: ['updated_at'],
      where: 'id = ?',
      whereArgs: ['merchant-user-review'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['updated_at'], old);
  });

  test('post-commit cleanup ambiguity never deletes live evidence', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final live = File(path.join(fixture.evidence.path, 'committed.bin'));
    await live.writeAsString('committed-evidence', flush: true);
    final journal = File('${fixture.evidence.path}.restore-journal.json');
    await journal.writeAsString(
      jsonEncode({
        'operationId': 'restore-cleanup-window',
        'previousPath': '${fixture.evidence.path}.restore-previous-missing',
        'stagingPath': '${fixture.evidence.path}.restore-missing',
        'phase': 'dbCommitted',
      }),
      flush: true,
    );

    await fixture.manager.recoverInterruptedRestore();

    expect(await live.exists(), isTrue);
    expect(await live.readAsString(), 'committed-evidence');
    expect(await journal.exists(), isFalse);
  });

  test('backup package keeps pre-write database state', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2025, 1, 1).toIso8601String();
    await fixture.database.database.insert('merchants', {
      'id': 'merchant-snapshot-review',
      'name': 'Before backup',
      'status': 'active',
      'normalized_name': 'before backup',
      'is_built_in': 0,
      'created_at': old,
      'updated_at': old,
    });
    await fixture.database.database.insert('provenances', {
      'id': 'prov-snapshot-review',
      'source_type': 'manual',
      'captured_at': old,
    });
    await fixture.database.database.insert('evidence_items', {
      'id': 'evidence-snapshot-review',
      'type': 'receipt',
      'original_name': 'slow.bin',
      'media_type': 'application/octet-stream',
      'provenance_id': 'prov-snapshot-review',
      'created_at': old,
      'local_file_name': 'slow.bin',
    });

    // Keep serialization active long enough for the competing write to be
    // submitted while the independent read transaction owns its WAL snapshot.
    final slowEvidence = File(path.join(fixture.evidence.path, 'slow.bin'));
    await slowEvidence.writeAsBytes(List<int>.filled(2 * 1024 * 1024, 7));
    final backup = File(path.join(fixture.root.path, 'snapshot.butlerlybackup'));
    final backupFuture = fixture.manager.createBackup(backup);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final writeFuture = fixture.database.database.update(
      'merchants',
      {'name': 'After backup', 'normalized_name': 'after backup'},
      where: 'id = ?',
      whereArgs: ['merchant-snapshot-review'],
    );

    await backupFuture;
    await writeFuture;
    await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

    final rows = await fixture.database.database.query(
      'merchants',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: ['merchant-snapshot-review'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Before backup');
  });

  test('merge purges newer unresolved duplicate state transactionally', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2025, 1, 1);
    await fixture.insertTransaction('tx-generated', old);
    final backup = File(path.join(fixture.root.path, 'generated.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    final future = DateTime.now().toUtc().add(const Duration(minutes: 5));
    await fixture.database.database.insert('duplicate_candidate_groups', {
      'id': 'generated-group',
      'transaction_date': '2025-01-01',
      'amount_coefficient': '100',
      'amount_scale': 2,
      'currency': 'USD',
      'direction': 'expense',
      'status': 'unresolved',
      'created_at': future.toIso8601String(),
      'updated_at': future.toIso8601String(),
    });
    await fixture.database.database.insert(
      'duplicate_candidate_group_transactions',
      {
        'group_id': 'generated-group',
        'transaction_id': 'tx-generated',
        'created_at': future.toIso8601String(),
      },
    );

    await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);

    expect(
      await fixture.database.database.query(
        'duplicate_candidate_groups',
        where: 'id = ?',
        whereArgs: ['generated-group'],
      ),
      isEmpty,
    );
    expect(
      await fixture.database.database.query(
        'duplicate_candidate_group_transactions',
        where: 'group_id = ?',
        whereArgs: ['generated-group'],
      ),
      isEmpty,
    );
    expect(await fixture.database.database.query('restore_context'), isEmpty);
  });

  test('corrupt evidence fails before generated local state is purged', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2025, 1, 1);
    await fixture.insertTransaction('tx-corrupt', old);
    await fixture.database.database.insert('provenances', {
      'id': 'prov-corrupt',
      'source_type': 'manual',
      'captured_at': old.toIso8601String(),
    });
    await fixture.database.database.insert('evidence_items', {
      'id': 'evidence-corrupt',
      'type': 'receipt',
      'original_name': 'corrupt.bin',
      'media_type': 'application/octet-stream',
      'provenance_id': 'prov-corrupt',
      'created_at': old.toIso8601String(),
      'local_file_name': 'corrupt.bin',
    });
    await File(path.join(fixture.evidence.path, 'corrupt.bin'))
        .writeAsString('evidence-before-corruption', flush: true);
    final backup = File(path.join(fixture.root.path, 'corrupt.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    await fixture.database.database.insert('review_issues', {
      'id': 'generated-review-after-backup',
      'transaction_id': 'tx-corrupt',
      'reason': 'generated',
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    final raf = await backup.open(mode: FileMode.append);
    final length = await backup.length();
    await raf.setPosition(length - 1);
    final original = await raf.readByte();
    await raf.setPosition(length - 1);
    await raf.writeByte(original ^ 0xff);
    await raf.close();

    await expectLater(
      fixture.manager.restore(backup, mode: LocalRestoreMode.merge),
      throwsFormatException,
    );

    expect(
      await fixture.database.database.query(
        'review_issues',
        where: 'id = ?',
        whereArgs: ['generated-review-after-backup'],
      ),
      hasLength(1),
    );
  });

  test('database failure rolls generated-state purge back with merge', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2025, 1, 1);
    await fixture.insertTransaction('tx-rollback', old);
    final backup = File(path.join(fixture.root.path, 'rollback.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    await fixture.database.database.insert('review_issues', {
      'id': 'generated-review-rollback',
      'transaction_id': 'tx-rollback',
      'reason': 'generated',
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await fixture.database.database.execute('''
      CREATE TRIGGER fail_restore_commit
      BEFORE INSERT ON restore_commits
      BEGIN
        SELECT RAISE(ABORT, 'forced restore failure');
      END
    ''');

    await expectLater(
      fixture.manager.restore(backup, mode: LocalRestoreMode.merge),
      throwsA(anything),
    );

    expect(
      await fixture.database.database.query(
        'review_issues',
        where: 'id = ?',
        whereArgs: ['generated-review-rollback'],
      ),
      hasLength(1),
    );
    expect(await fixture.database.database.query('restore_context'), isEmpty);
  });

  test('concurrent edit during evidence staging keeps timestamp and wins merge', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2025, 1, 1).toIso8601String();
    await fixture.database.database.insert('merchants', {
      'id': 'merchant-staging-race',
      'name': 'Backup value',
      'status': 'active',
      'normalized_name': 'backup value',
      'is_built_in': 0,
      'created_at': old,
      'updated_at': old,
    });
    await fixture.database.database.insert('provenances', {
      'id': 'prov-staging-race',
      'source_type': 'manual',
      'captured_at': old,
    });
    await fixture.database.database.insert('evidence_items', {
      'id': 'evidence-staging-race',
      'type': 'receipt',
      'original_name': 'staging-race.bin',
      'media_type': 'application/octet-stream',
      'provenance_id': 'prov-staging-race',
      'created_at': old,
      'local_file_name': 'staging-race.bin',
    });
    await File(path.join(fixture.evidence.path, 'staging-race.bin'))
        .writeAsBytes(List<int>.filled(8 * 1024 * 1024, 11), flush: true);
    final backup = File(path.join(fixture.root.path, 'staging-race.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    final restoreFuture = fixture.manager.restore(
      backup,
      mode: LocalRestoreMode.merge,
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await fixture.database.database.update(
      'merchants',
      {'name': 'Concurrent local edit', 'normalized_name': 'concurrent local edit'},
      where: 'id = ?',
      whereArgs: ['merchant-staging-race'],
    );
    await restoreFuture;

    final rows = await fixture.database.database.query(
      'merchants',
      columns: ['name', 'updated_at'],
      where: 'id = ?',
      whereArgs: ['merchant-staging-race'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Concurrent local edit');
    final updatedAt = DateTime.parse(rows.single['updated_at']! as String);
    expect(updatedAt.isAfter(DateTime.utc(2025, 1, 1)), isTrue);
    expect(await fixture.database.database.query('restore_context'), isEmpty);
  });

  test('merge chooses a safe suffix when evidence remap target is occupied', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2025, 1, 1).toIso8601String();
    await fixture.database.database.insert('provenances', {
      'id': 'prov-remap',
      'source_type': 'manual',
      'captured_at': old,
    });
    await fixture.database.database.insert('evidence_items', {
      'id': 'evidence-remap',
      'type': 'receipt',
      'original_name': 'receipt.bin',
      'media_type': 'application/octet-stream',
      'provenance_id': 'prov-remap',
      'created_at': old,
      'local_file_name': 'receipt.bin',
    });
    const backupBytes = 'backup-evidence';
    await File(path.join(fixture.evidence.path, 'receipt.bin'))
        .writeAsString(backupBytes, flush: true);
    final backup = File(path.join(fixture.root.path, 'remap.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    await File(path.join(fixture.evidence.path, 'receipt.bin'))
        .writeAsString('newer-local-evidence', flush: true);
    final hash = sha256Bytes(utf8.encode(backupBytes));
    final occupiedRemap = File(
      path.join(fixture.evidence.path, 'receipt.backup-$hash.bin'),
    );
    await occupiedRemap.writeAsString('unrelated-local-evidence', flush: true);

    await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);

    expect(await occupiedRemap.readAsString(), 'unrelated-local-evidence');
    expect(
      await File(path.join(fixture.evidence.path, 'receipt.bin')).readAsString(),
      'newer-local-evidence',
    );
    final safeRemap = File(
      path.join(fixture.evidence.path, 'receipt.backup-$hash-1.bin'),
    );
    expect(await safeRemap.readAsString(), backupBytes);
    final rows = await fixture.database.database.query(
      'evidence_items',
      columns: ['local_file_name'],
      where: 'id = ?',
      whereArgs: ['evidence-remap'],
    );
    expect(rows.single['local_file_name'], 'receipt.backup-$hash-1.bin');
  });
}

final class _Fixture {
  _Fixture(this.root, this.evidence, this.database, this.manager);

  final Directory root;
  final Directory evidence;
  final LocalDatabase database;
  final LocalBackupManager manager;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('butlerly-review-fixes-');
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
    return _Fixture(root, evidence, database, LocalBackupManager(database, data));
  }

  Future<void> insertTransaction(String id, DateTime timestamp) async {
    await database.database.insert('transactions', {
      'id': id,
      'unknown_time_reason': 'unknown',
      'amount_coefficient': '100',
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
