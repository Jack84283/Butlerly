import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('manifest carries backup and app identity metadata', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.insertTransaction('tx-manifest');
    final backup = File(
      path.join(fixture.root.path, 'manifest.butlerlybackup'),
    );

    await fixture.manager.createBackup(backup);

    final manifest = await _readManifest(backup);
    expect(manifest['backupId'], isA<String>());
    expect((manifest['backupId']! as String), isNotEmpty);
    expect(manifest['appVersion'], '1.0.0');
    expect(manifest['appBuild'], '1');
    expect(manifest['schemaVersion'], 11);
  });

  test(
    'replace creates a safety backup that can recover prior state',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-safety', description: 'backup state');
      final source = File(
        path.join(fixture.root.path, 'source.butlerlybackup'),
      );
      await fixture.manager.createBackup(source);
      await fixture.database.database.update(
        'transactions',
        {
          'description': 'current state',
          'updated_at': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: ['tx-safety'],
      );

      await fixture.manager.restore(source, mode: LocalRestoreMode.replace);

      final safetyDirectory = await fixture.data.safetyBackupDirectory();
      final safetyFiles = await safetyDirectory
          .list()
          .where(
            (entity) =>
                entity is File && entity.path.endsWith('.butlerlybackup'),
          )
          .cast<File>()
          .toList();
      expect(safetyFiles, hasLength(1));
      final afterReplace = await fixture.database.database.query(
        'transactions',
        columns: ['description'],
        where: 'id = ?',
        whereArgs: ['tx-safety'],
      );
      expect(afterReplace.single['description'], 'backup state');

      await fixture.manager.restore(
        safetyFiles.single,
        mode: LocalRestoreMode.replace,
      );

      final recovered = await fixture.database.database.query(
        'transactions',
        columns: ['description'],
        where: 'id = ?',
        whereArgs: ['tx-safety'],
      );
      expect(recovered.single['description'], 'current state');
    },
  );

  test(
    'restore keeps durable decisions and drops generated workflow state',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final now = DateTime.utc(2026, 9, 1).toIso8601String();
      await fixture.insertTransaction('tx-a');
      await fixture.insertTransaction('tx-b');
      await fixture.insertTransaction('tx-c');
      await fixture.database.database.insert('provenances', {
        'id': 'prov-workflow',
        'source_type': 'manual',
        'captured_at': now,
      });
      await fixture.database.database.insert('review_issues', {
        'id': 'review-open',
        'transaction_id': 'tx-a',
        'reason': 'incomplete',
        'status': 'open',
        'created_at': now,
      });
      await fixture.database.database.insert('review_issues', {
        'id': 'review-closed',
        'transaction_id': 'tx-a',
        'reason': 'incomplete',
        'status': 'resolved',
        'created_at': now,
        'closed_at': now,
      });
      await fixture.database.database.insert('suggestions', {
        'id': 'suggestion-open',
        'transaction_id': 'tx-a',
        'target': 'category',
        'proposed_value': 'category.food',
        'method': 'local',
        'status': 'proposed',
        'provenance_id': 'prov-workflow',
        'created_at': now,
      });
      await fixture.database.database.insert('suggestions', {
        'id': 'suggestion-decided',
        'transaction_id': 'tx-a',
        'target': 'category',
        'proposed_value': 'category.food',
        'method': 'local',
        'status': 'accepted',
        'provenance_id': 'prov-workflow',
        'created_at': now,
        'decided_at': now,
      });
      await _insertCandidate(
        fixture,
        id: 'candidate-proposed',
        receiptId: 'tx-a',
        paymentId: 'tx-b',
        status: 'proposed',
        now: now,
      );
      await _insertCandidate(
        fixture,
        id: 'candidate-rejected',
        receiptId: 'tx-a',
        paymentId: 'tx-c',
        status: 'rejected',
        now: now,
      );
      await _insertDuplicateGroup(
        fixture,
        id: 'duplicate-open',
        status: 'unresolved',
        now: now,
      );
      await _insertDuplicateGroup(
        fixture,
        id: 'duplicate-decided',
        status: 'keepBoth',
        now: now,
      );
      final backup = File(
        path.join(fixture.root.path, 'workflow.butlerlybackup'),
      );

      await fixture.manager.createBackup(backup);
      await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

      expect(
        await _ids(fixture, 'review_issues'),
        containsAll(<String>['review-closed']),
      );
      expect(
        await _ids(fixture, 'review_issues'),
        isNot(contains('review-open')),
      );
      expect(
        await _ids(fixture, 'suggestions'),
        containsAll(<String>['suggestion-decided']),
      );
      expect(
        await _ids(fixture, 'suggestions'),
        isNot(contains('suggestion-open')),
      );
      expect(
        await _ids(fixture, 'reconciliation_candidates'),
        containsAll(<String>['candidate-rejected']),
      );
      expect(
        await _ids(fixture, 'reconciliation_candidates'),
        isNot(contains('candidate-proposed')),
      );
      expect(
        await _ids(fixture, 'duplicate_candidate_groups'),
        containsAll(<String>['duplicate-decided']),
      );
      expect(
        await _ids(fixture, 'duplicate_candidate_groups'),
        isNot(contains('duplicate-open')),
      );
    },
  );
}

Future<void> _insertCandidate(
  _Fixture fixture, {
  required String id,
  required String receiptId,
  required String paymentId,
  required String status,
  required String now,
}) => fixture.database.database.insert('reconciliation_candidates', {
  'id': id,
  'receipt_transaction_id': receiptId,
  'payment_transaction_id': paymentId,
  'score': 0.9,
  'reasons_json': '[]',
  'status': status,
  'created_at': now,
  'updated_at': now,
});

Future<void> _insertDuplicateGroup(
  _Fixture fixture, {
  required String id,
  required String status,
  required String now,
}) async {
  await fixture.database.database.insert('duplicate_candidate_groups', {
    'id': id,
    'transaction_date': '2026-09-01',
    'amount_coefficient': '100',
    'amount_scale': 2,
    'currency': 'USD',
    'direction': 'expense',
    'status': status,
    'created_at': now,
    'updated_at': now,
  });
  await fixture.database.database.insert(
    'duplicate_candidate_group_transactions',
    {'group_id': id, 'transaction_id': 'tx-a'},
  );
  await fixture.database.database.insert(
    'duplicate_candidate_group_transactions',
    {'group_id': id, 'transaction_id': 'tx-b'},
  );
}

Future<List<String>> _ids(_Fixture fixture, String table) async {
  final rows = await fixture.database.database.query(table, columns: ['id']);
  return rows.map((row) => row['id']! as String).toList(growable: false);
}

Future<Map<String, Object?>> _readManifest(File file) async {
  final handle = await file.open(mode: FileMode.read);
  try {
    final magic = await handle.read(utf8.encode('BUTLERLYBACKUP2').length);
    expect(utf8.decode(magic), 'BUTLERLYBACKUP2');
    final metadataLength = int64FromBytes(await handle.read(8));
    await handle.read(64);
    final metadata = jsonDecode(utf8.decode(await handle.read(metadataLength)));
    return ((metadata as Map)['manifest']! as Map).cast<String, Object?>();
  } finally {
    await handle.close();
  }
}

final class _Fixture {
  _Fixture(this.root, this.evidence, this.database, this.data, this.manager);

  final Directory root;
  final Directory evidence;
  final LocalDatabase database;
  final LocalDataManager data;
  final LocalBackupManager manager;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-backup-contract-',
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
    return _Fixture(
      root,
      evidence,
      database,
      data,
      LocalBackupManager(database, data),
    );
  }

  Future<void> insertTransaction(String id, {String? description}) async {
    final now = DateTime.utc(2026, 9, 1).toIso8601String();
    await database.database.insert('transactions', {
      'id': id,
      'unknown_time_reason': 'unknown',
      'amount_coefficient': '100',
      'amount_scale': 2,
      'currency': 'USD',
      'direction': 'expense',
      'source_type': 'manual',
      'status': 'active',
      'description': description,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> dispose() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
