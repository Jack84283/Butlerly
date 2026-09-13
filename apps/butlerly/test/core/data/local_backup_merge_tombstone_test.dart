import 'dart:convert';
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

  test('merge does not resurrect a review issue deleted after backup', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2026, 1, 1);
    await fixture.insertTransaction('tx-review', old);
    await fixture.database.database.insert('review_issues', {
      'id': 'review-1',
      'transaction_id': 'tx-review',
      'reason': 'uncategorized',
      'status': 'active',
      'created_at': old.toIso8601String(),
    });
    final backup = File(path.join(fixture.root.path, 'review.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    await fixture.database.database.delete(
      'review_issues',
      where: 'id = ?',
      whereArgs: ['review-1'],
    );
    final future = DateTime.now().toUtc().add(const Duration(minutes: 5));
    await fixture.database.database.update(
      'entity_tombstones',
      {'deleted_at': future.toIso8601String()},
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['review_issues', 'review-1'],
    );

    await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);

    expect(
      await fixture.database.database.query(
        'review_issues',
        where: 'id = ?',
        whereArgs: ['review-1'],
      ),
      isEmpty,
    );
  });

  test('merge keeps a durable duplicate membership re-added after backup', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2026, 1, 1);
    await fixture.insertTransaction('tx-duplicate', old);
    await fixture.database.database.insert('duplicate_candidate_groups', {
      'id': 'duplicate-group-1',
      'transaction_date': '2026-01-01',
      'amount_coefficient': '100',
      'amount_scale': 2,
      'currency': 'USD',
      'direction': 'expense',
      // keepBoth is a durable user decision; unresolved groups are derived and
      // intentionally regenerated rather than merged.
      'status': 'keepBoth',
      'created_at': old.toIso8601String(),
      'updated_at': old.toIso8601String(),
    });
    await fixture.database.database.insert(
      'duplicate_candidate_group_transactions',
      {
        'group_id': 'duplicate-group-1',
        'transaction_id': 'tx-duplicate',
        'created_at': old.toIso8601String(),
      },
    );
    await fixture.database.database.delete(
      'duplicate_candidate_group_transactions',
      where: 'group_id = ? AND transaction_id = ?',
      whereArgs: ['duplicate-group-1', 'tx-duplicate'],
    );
    final backup = File(path.join(fixture.root.path, 'membership.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    final future = DateTime.now().toUtc().add(const Duration(minutes: 5));
    await fixture.database.database.insert(
      'duplicate_candidate_group_transactions',
      {
        'group_id': 'duplicate-group-1',
        'transaction_id': 'tx-duplicate',
        'created_at': future.toIso8601String(),
      },
    );

    await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);

    final memberships = await fixture.database.database.query(
      'duplicate_candidate_group_transactions',
      where: 'group_id = ? AND transaction_id = ?',
      whereArgs: ['duplicate-group-1', 'tx-duplicate'],
    );
    expect(memberships, hasLength(1));
    expect(memberships.single['created_at'], future.toIso8601String());
    expect(
      await fixture.database.database.query(
        'entity_tombstones',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [
          'duplicate_candidate_group_transactions',
          'duplicate-group-1|tx-duplicate',
        ],
      ),
      isEmpty,
    );
  });

  test('prepared-phase recovery uses directory state and clears restore context', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final evidence = fixture.evidence;
    await File(path.join(evidence.path, 'receipt.bin')).writeAsString('new');
    final operation = 'restore-rename-boundary';
    final previous = Directory('${evidence.path}.restore-previous-$operation')
      ..createSync(recursive: true);
    await File(path.join(previous.path, 'receipt.bin')).writeAsString('old');
    await fixture.database.database.insert('restore_context', {
      'id': 1,
      'backup_time': DateTime.utc(2026, 1, 1).toIso8601String(),
    });
    final journal = File('${evidence.path}.restore-journal.json');
    await journal.writeAsString(
      jsonEncode({
        'operationId': operation,
        'previousPath': previous.path,
        'stagingPath': '${evidence.path}.missing-staging',
        'phase': 'prepared',
      }),
    );

    await fixture.manager.recoverInterruptedRestore();

    expect(
      await File(path.join(evidence.path, 'receipt.bin')).readAsString(),
      'old',
    );
    expect(await fixture.database.database.query('restore_context'), isEmpty);
    expect(await journal.exists(), isFalse);
  });
}

final class _Fixture {
  _Fixture(this.root, this.evidence, this.database, this.manager);

  final Directory root;
  final Directory evidence;
  final LocalDatabase database;
  final LocalBackupManager manager;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('butlerly-merge-state-');
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
