import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
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
    expect(manifest['schemaVersion'], 13);
  });

  test(
    'new builds restore schema 12 backups without statement duplicate evidence',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-schema-12-a');
      await fixture.insertTransaction('tx-schema-12-b');
      await _insertDuplicateGroup(
        fixture,
        id: 'duplicate-schema-12',
        status: 'keepBoth',
        now: DateTime.utc(2026, 9, 1).toIso8601String(),
        statementRows: '[{"statementId":"statement-12","rowId":"row-12"}]',
        transactionIds: ['tx-schema-12-a', 'tx-schema-12-b'],
      );
      final backup = File(
        path.join(fixture.root.path, 'schema-12.butlerlybackup'),
      );
      await fixture.manager.createBackup(backup);
      await _downgradeBackupToV12(backup);

      await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

      expect(await _ids(fixture, 'transactions'), contains('tx-schema-12-a'));
      final groups = await fixture.database.database.query(
        'duplicate_candidate_groups',
        columns: ['statement_rows'],
        where: 'id = ?',
        whereArgs: ['duplicate-schema-12'],
      );
      expect(groups.single['statement_rows'], anyOf(isNull, '[]'));
    },
  );

  test('new builds restore schema 11 backups without newer tables', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.insertTransaction('tx-schema-11');
    final backup = File(
      path.join(fixture.root.path, 'schema-11.butlerlybackup'),
    );
    await fixture.manager.createBackup(backup);
    await _downgradeBackupToV11(backup);

    await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

    expect(await _ids(fixture, 'transactions'), contains('tx-schema-11'));
    expect(await _ids(fixture, 'recurring_pattern_decisions'), isEmpty);
  });

  test(
    'replace restore clears recurring decisions absent from the backup',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-source');
      final backup = File(
        path.join(
          fixture.root.path,
          'without-recurring-decision.butlerlybackup',
        ),
      );
      await fixture.manager.createBackup(backup);
      await fixture.database.database.insert('recurring_pattern_decisions', {
        'id': 'stale-decision',
        'pattern_key': 'unrelated|expense|USD||',
        'status': 'confirmed',
        'cadence': 'monthly',
        'interval_days': 30,
        'expected_amount_coefficient': '1000',
        'expected_amount_scale': 2,
        'created_at': DateTime.utc(2026, 9, 1).toIso8601String(),
        'updated_at': DateTime.utc(2026, 9, 1).toIso8601String(),
      });

      await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

      expect(await _ids(fixture, 'recurring_pattern_decisions'), isEmpty);
    },
  );

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
        transactionIds: ['tx-a', 'tx-b', 'tx-c'],
      );
      await _insertDuplicateGroup(
        fixture,
        id: 'duplicate-statement-candidate',
        status: 'unresolved',
        now: now,
        statementRows: '[{"statementId":"statement-1","rowId":"row-1"}]',
      );
      await _insertDuplicateGroup(
        fixture,
        id: 'duplicate-decided',
        status: 'keepBoth',
        now: now,
      );
      await fixture.database.database.insert('recurring_pattern_decisions', {
        'id': 'recurring-decision-backup',
        'pattern_key': 'merchant|expense|USD||',
        'status': 'corrected',
        'cadence': 'monthly',
        'interval_days': 31,
        'expected_amount_coefficient': '4250',
        'expected_amount_scale': 2,
        'created_at': now,
        'updated_at': now,
      });
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
      expect(
        await _ids(fixture, 'duplicate_candidate_groups'),
        contains('duplicate-statement-candidate'),
      );
      expect(
        await _ids(fixture, 'recurring_pattern_decisions'),
        contains('recurring-decision-backup'),
      );
    },
  );

  test('backup and restore preserves stale duplicate repair context', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.insertTransaction('tx-stale-a');
    await fixture.insertTransaction('tx-stale-b');
    await _insertDuplicateGroup(
      fixture,
      id: 'duplicate-stale-repair',
      status: 'unresolved',
      now: DateTime.utc(2026, 9, 1).toIso8601String(),
      transactionIds: ['tx-stale-a', 'tx-stale-b'],
    );
    await fixture.database.database.update(
      'transactions',
      {'amount_coefficient': '200'},
      where: 'id = ?',
      whereArgs: ['tx-stale-b'],
    );
    final backup = File(
      path.join(fixture.root.path, 'stale-duplicate.butlerlybackup'),
    );

    await fixture.manager.createBackup(backup);
    await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

    expect(
      await _ids(fixture, 'duplicate_candidate_groups'),
      contains('duplicate-stale-repair'),
    );
    final restored = (await SqliteDuplicateCandidateGroupRepository(
      fixture.database.persistenceDatabase,
    ).list()).single;
    expect(restored.status, DuplicateCandidateGroupStatus.unresolved);
    expect(restored.integrityIssue?.code, 'staleDuplicateGroup');
  });

  test(
    'archive backup and restore preserves unresolved historical duplicate decisions',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-archived-a');
      await fixture.insertTransaction('tx-archived-b');
      await _insertDuplicateGroup(
        fixture,
        id: 'duplicate-archived-history',
        status: 'unresolved',
        now: DateTime.utc(2026, 9, 1).toIso8601String(),
        transactionIds: ['tx-archived-a', 'tx-archived-b'],
      );
      await fixture.database.database.update(
        'transactions',
        {'status': 'archived'},
        where: 'id = ?',
        whereArgs: ['tx-archived-b'],
      );
      final before = (await SqliteDuplicateCandidateGroupRepository(
        fixture.database.persistenceDatabase,
      ).list()).single;
      expect(
        selectCanonicalTransactions(
          source: await SqliteTransactionRepository(
            fixture.database.persistenceDatabase,
          ).listAll(),
          duplicateGroups: [before],
        ).transactions,
        hasLength(1),
      );
      final backup = File(
        path.join(fixture.root.path, 'archived-duplicate.butlerlybackup'),
      );

      await fixture.manager.createBackup(backup);
      await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);
      final transactions = SqliteTransactionRepository(
        fixture.database.persistenceDatabase,
      );
      final groups = SqliteDuplicateCandidateGroupRepository(
        fixture.database.persistenceDatabase,
      );
      final rebuilt = await RebuildDuplicateGroupsAfterRestore(
        groups,
        const SystemApplicationClock(),
        transactions: transactions,
      )();
      expect(rebuilt, isA<ApplicationSuccess<List<DuplicateCandidateGroup>>>());
      final after = (await groups.list()).single;
      expect(after.status, DuplicateCandidateGroupStatus.unresolved);
      expect(after.transactionIds, hasLength(2));
      expect(
        selectCanonicalTransactions(
          source: await transactions.listAll(),
          duplicateGroups: [after],
        ).transactions,
        hasLength(1),
      );
    },
  );

  test(
    'merge restore preserves a local archived duplicate group absent from backup',
    () async {
      final target = await _Fixture.create();
      final source = await _Fixture.create();
      addTearDown(target.dispose);
      addTearDown(source.dispose);
      await target.insertTransaction('tx-local-active');
      await target.insertTransaction('tx-local-archived');
      await _insertDuplicateGroup(
        target,
        id: 'duplicate-local-archived-history',
        status: 'unresolved',
        now: DateTime.utc(2026, 9, 1).toIso8601String(),
        transactionIds: ['tx-local-active', 'tx-local-archived'],
      );
      await target.database.database.update(
        'transactions',
        {'status': 'archived'},
        where: 'id = ?',
        whereArgs: ['tx-local-archived'],
      );
      await source.insertTransaction('tx-incoming');
      final backup = File(
        path.join(source.root.path, 'merge-source.butlerlybackup'),
      );
      await source.manager.createBackup(backup);

      await target.manager.restore(backup, mode: LocalRestoreMode.merge);

      final transactions = SqliteTransactionRepository(
        target.database.persistenceDatabase,
      );
      final groups = SqliteDuplicateCandidateGroupRepository(
        target.database.persistenceDatabase,
      );
      final rebuilt = await RebuildDuplicateGroupsAfterRestore(
        groups,
        const SystemApplicationClock(),
        transactions: transactions,
      )();
      expect(rebuilt, isA<ApplicationSuccess<List<DuplicateCandidateGroup>>>());
      final preserved = (await groups.list())
          .where((group) => group.id == 'duplicate-local-archived-history')
          .single;
      expect(preserved.status, DuplicateCandidateGroupStatus.unresolved);
      expect(preserved.transactionIds, hasLength(2));
      final canonicalIds = selectCanonicalTransactions(
        source: await transactions.listAll(),
        duplicateGroups: [preserved],
      ).transactions.map((transaction) => transaction.id.value);
      expect(canonicalIds, containsAll(['tx-local-active', 'tx-incoming']));
      expect(canonicalIds, isNot(contains('tx-local-archived')));
    },
  );

  test(
    'backup and restore preserves malformed duplicate repair context',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-malformed-a');
      await fixture.insertTransaction('tx-malformed-b');
      await fixture.database.database.insert('duplicate_candidate_groups', {
        'id': 'duplicate-malformed-dates',
        'transaction_date': '2026-09-01',
        'amount_coefficient': '100',
        'amount_scale': 2,
        'currency': 'USD',
        'direction': 'expense',
        'status': 'unresolved',
        'created_at': 'not-a-timestamp',
        'updated_at': 'also-not-a-timestamp',
      });
      await fixture.database.database
          .insert('duplicate_candidate_group_transactions', {
            'group_id': 'duplicate-malformed-dates',
            'transaction_id': 'tx-malformed-a',
          });
      await fixture.database.database
          .insert('duplicate_candidate_group_transactions', {
            'group_id': 'duplicate-malformed-dates',
            'transaction_id': 'tx-malformed-b',
          });
      final backup = File(
        path.join(fixture.root.path, 'malformed-duplicate.butlerlybackup'),
      );

      await fixture.manager.createBackup(backup);
      await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

      final restored = (await SqliteDuplicateCandidateGroupRepository(
        fixture.database.persistenceDatabase,
      ).list()).single;
      expect(restored.id, 'duplicate-malformed-dates');
      expect(restored.status, DuplicateCandidateGroupStatus.unresolved);
      expect(restored.integrityIssue?.code, 'malformedDuplicateGroup');
    },
  );

  test(
    'merge restore preserves active-only duplicate repair contexts',
    () async {
      final target = await _Fixture.create();
      final source = await _Fixture.create();
      addTearDown(target.dispose);
      addTearDown(source.dispose);
      final now = DateTime.utc(2026, 9, 1).toIso8601String();

      await target.insertTransaction('tx-merge-stale-a');
      await target.insertTransaction('tx-merge-stale-b');
      await _insertDuplicateGroup(
        target,
        id: 'duplicate-merge-stale',
        status: 'unresolved',
        now: now,
        transactionIds: ['tx-merge-stale-a', 'tx-merge-stale-b'],
      );
      await target.database.database.update(
        'transactions',
        {'amount_coefficient': '200'},
        where: 'id = ?',
        whereArgs: ['tx-merge-stale-b'],
      );

      await target.insertTransaction('tx-merge-incomplete');
      await _insertDuplicateGroup(
        target,
        id: 'duplicate-merge-incomplete',
        status: 'unresolved',
        now: now,
        transactionIds: ['tx-merge-incomplete'],
      );

      await target.insertTransaction('tx-merge-malformed-a');
      await target.insertTransaction('tx-merge-malformed-b');
      await target.database.database.insert('duplicate_candidate_groups', {
        'id': 'duplicate-merge-malformed',
        'transaction_date': '2026-09-01',
        'amount_coefficient': '100',
        'amount_scale': 2,
        'currency': 'USD',
        'direction': 'expense',
        'status': 'unresolved',
        'created_at': 'not-a-timestamp',
        'updated_at': 'also-not-a-timestamp',
      });
      for (final transactionId in [
        'tx-merge-malformed-a',
        'tx-merge-malformed-b',
      ]) {
        await target.database.database.insert(
          'duplicate_candidate_group_transactions',
          {
            'group_id': 'duplicate-merge-malformed',
            'transaction_id': transactionId,
          },
        );
      }

      await source.insertTransaction('tx-merge-incoming');
      final backup = File(
        path.join(source.root.path, 'merge-repair-context.butlerlybackup'),
      );
      await source.manager.createBackup(backup);

      await target.manager.restore(backup, mode: LocalRestoreMode.merge);

      final transactions = SqliteTransactionRepository(
        target.database.persistenceDatabase,
      );
      final groups = SqliteDuplicateCandidateGroupRepository(
        target.database.persistenceDatabase,
      );
      final rebuilt = await RebuildDuplicateGroupsAfterRestore(
        groups,
        const SystemApplicationClock(),
        transactions: transactions,
      )();
      expect(rebuilt, isA<ApplicationSuccess<List<DuplicateCandidateGroup>>>());
      final restored = await groups.list();
      expect(
        restored.map((group) => group.id),
        containsAll([
          'duplicate-merge-stale',
          'duplicate-merge-incomplete',
          'duplicate-merge-malformed',
        ]),
      );
      expect(
        restored
            .singleWhere((group) => group.id == 'duplicate-merge-stale')
            .integrityIssue
            ?.code,
        'staleDuplicateGroup',
      );
      expect(
        restored
            .singleWhere((group) => group.id == 'duplicate-merge-incomplete')
            .integrityIssue
            ?.code,
        'incompleteDuplicateGroup',
      );
      expect(
        restored
            .singleWhere((group) => group.id == 'duplicate-merge-malformed')
            .integrityIssue
            ?.code,
        'malformedDuplicateGroup',
      );
      final canonical = selectCanonicalTransactions(
        source: await transactions.listAll(),
        duplicateGroups: restored,
      );
      // The edited member is outside the current duplicate key and therefore
      // remains counted, while the newly rebuilt current-key group remains
      // unresolved and counts its matching members once.
      expect(canonical.transactions, hasLength(2));
      expect(
        canonical.transactions.map((value) => value.id.value),
        containsAll(['tx-merge-incoming', 'tx-merge-stale-b']),
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
  String? statementRows,
  List<String> transactionIds = const ['tx-a', 'tx-b'],
}) async {
  await fixture.database.database.insert('duplicate_candidate_groups', {
    'id': id,
    'transaction_date': '2026-09-01',
    'amount_coefficient': '100',
    'amount_scale': 2,
    'currency': 'USD',
    'direction': 'expense',
    'status': status,
    ...?(statementRows == null ? null : {'statement_rows': statementRows}),
    'created_at': now,
    'updated_at': now,
  });
  await fixture.database.database.insert(
    'duplicate_candidate_group_transactions',
    {'group_id': id, 'transaction_id': transactionIds.first},
  );
  for (final transactionId in transactionIds.skip(1)) {
    await fixture.database.database.insert(
      'duplicate_candidate_group_transactions',
      {'group_id': id, 'transaction_id': transactionId},
    );
  }
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

Future<void> _downgradeBackupToV11(File backup) async {
  final bytes = await backup.readAsBytes();
  final magic = utf8.encode('BUTLERLYBACKUP2');
  final metadataLength = int64FromBytes(
    bytes.sublist(magic.length, magic.length + 8),
  );
  final metadataStart = magic.length + 8 + 64;
  final metadataEnd = metadataStart + metadataLength;
  final metadata =
      jsonDecode(utf8.decode(bytes.sublist(metadataStart, metadataEnd)))
          as Map<String, Object?>;
  final manifest = (metadata['manifest']! as Map).cast<String, Object?>();
  final tables = (metadata['tables']! as Map).cast<String, Object?>();
  manifest['schemaVersion'] = 11;
  tables.remove('recurring_pattern_decisions');
  final encoded = utf8.encode(jsonEncode(metadata));
  await backup.writeAsBytes([
    ...magic,
    ...int64Bytes(encoded.length),
    ...ascii.encode(sha256Bytes(encoded)),
    ...encoded,
    ...bytes.sublist(metadataEnd),
  ], flush: true);
}

Future<void> _downgradeBackupToV12(File backup) async {
  final bytes = await backup.readAsBytes();
  final magic = utf8.encode('BUTLERLYBACKUP2');
  final metadataLength = int64FromBytes(
    bytes.sublist(magic.length, magic.length + 8),
  );
  final metadataStart = magic.length + 8 + 64;
  final metadataEnd = metadataStart + metadataLength;
  final metadata =
      (jsonDecode(utf8.decode(bytes.sublist(metadataStart, metadataEnd)))
          as Map<String, Object?>);
  final manifest = (metadata['manifest']! as Map).cast<String, Object?>();
  final tables = (metadata['tables']! as Map).cast<String, Object?>();
  manifest['schemaVersion'] = 12;
  final groups = (tables['duplicate_candidate_groups'] as List?) ?? const [];
  for (final value in groups) {
    if (value is Map) value.remove('statement_rows');
  }
  final encoded = utf8.encode(jsonEncode(metadata));
  await backup.writeAsBytes([
    ...magic,
    ...int64Bytes(encoded.length),
    ...ascii.encode(sha256Bytes(encoded)),
    ...encoded,
    ...bytes.sublist(metadataEnd),
  ], flush: true);
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
    await database.database.insert('provenances', {
      'id': '$id-provenance',
      'source_type': 'import',
      'captured_at': now,
      'original_representation': description ?? id,
    });
    await database.database.insert('transactions', {
      'id': id,
      'unknown_time_reason': 'unknown',
      'amount_coefficient': '100',
      'amount_scale': 2,
      'currency': 'USD',
      'direction': 'expense',
      'transaction_date': '2026-09-01',
      'source_type': 'manual',
      'status': 'active',
      'description': description,
      'created_at': now,
      'updated_at': now,
    });
    await database.database.insert('transaction_provenances', {
      'transaction_id': id,
      'provenance_id': '$id-provenance',
    });
  }

  Future<void> dispose() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
