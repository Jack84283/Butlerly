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

  test('backup and replace restore preserve saved budgets', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();
    await fixture.database.database.insert('budgets', {
      'id': 'budget-groceries',
      'scope': 'category',
      'scope_id': 'category.food.groceries',
      'currency': 'USD',
      'amount': '500.00',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await fixture.database.database.insert('tags', {
      'id': 'tag.user-owned',
      'name': 'User-owned tag',
      'status': 'active',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await fixture.database.database.insert('tag_translations', {
      'tag_id': 'tag.user-owned',
      'locale': 'en',
      'label': 'User-owned tag',
    });
    final backup = File(path.join(fixture.root.path, 'budgets.butlerlybackup'));
    await fixture.backups.createBackup(backup);
    await fixture.database.database.delete('budgets');
    await fixture.database.database.delete(
      'tags',
      where: 'id = ?',
      whereArgs: ['tag.user-owned'],
    );

    await fixture.backups.restore(backup, mode: LocalRestoreMode.replace);

    final rows = await fixture.database.database.query('budgets');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'budget-groceries');
    expect(rows.single['scope'], 'category');
    expect(rows.single['scope_id'], 'category.food.groceries');
    expect(rows.single['currency'], 'USD');
    expect(rows.single['amount'], '500.00');
    expect(
      (await fixture.database.database.query(
        'tags',
        where: 'id = ?',
        whereArgs: ['tag.user-owned'],
      )).single['name'],
      'User-owned tag',
    );
  });

  test(
    'merge preserves local edits to durable reference and translation data',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const timestamp = '2026-10-01T00:00:00.000Z';
      await fixture.database.database.insert('categories', {
        'id': 'user.category.merge',
        'name': 'Merge category',
        'origin': 'user',
        'parent_id': null,
        'status': 'active',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await fixture.database.database.insert('category_translations', {
        'category_id': 'user.category.merge',
        'locale': 'en',
        'label': 'Backup category label',
      });
      await fixture.database.database.insert('tags', {
        'id': 'user.tag.merge',
        'name': 'Merge tag',
        'status': 'active',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await fixture.database.database.insert('tag_translations', {
        'tag_id': 'user.tag.merge',
        'locale': 'en',
        'label': 'Backup tag label',
      });
      await fixture.database.database.insert('reference_data', {
        'id': 'user.reference.merge',
        'code': 'backup-reference',
        'type': 'merge-test',
        'origin': 'user',
        'status': 'active',
      });
      await fixture.database.database.insert('reference_data_translations', {
        'reference_data_id': 'user.reference.merge',
        'locale': 'en',
        'label': 'Backup reference label',
      });

      final backup = File(
        path.join(fixture.root.path, 'reference-merge.butlerly'),
      );
      await fixture.backups.createBackup(backup);
      await fixture.database.database.update(
        'category_translations',
        {'label': 'Local category label'},
        where: 'category_id = ? AND locale = ?',
        whereArgs: ['user.category.merge', 'en'],
      );
      await fixture.database.database.update(
        'tag_translations',
        {'label': 'Local tag label'},
        where: 'tag_id = ? AND locale = ?',
        whereArgs: ['user.tag.merge', 'en'],
      );
      await fixture.database.database.update(
        'reference_data',
        {'code': 'local-reference'},
        where: 'id = ?',
        whereArgs: ['user.reference.merge'],
      );
      await fixture.database.database.update(
        'reference_data_translations',
        {'label': 'Local reference label'},
        where: 'reference_data_id = ? AND locale = ?',
        whereArgs: ['user.reference.merge', 'en'],
      );

      final inspection = await fixture.backups.inspect(backup);
      expect(inspection.changes.masterDataChanged, greaterThanOrEqualTo(4));
      await fixture.backups.restore(backup, mode: LocalRestoreMode.merge);

      expect(
        (await fixture.database.database.query(
          'category_translations',
          where: 'category_id = ? AND locale = ?',
          whereArgs: ['user.category.merge', 'en'],
        )).single['label'],
        'Local category label',
      );
      expect(
        (await fixture.database.database.query(
          'tag_translations',
          where: 'tag_id = ? AND locale = ?',
          whereArgs: ['user.tag.merge', 'en'],
        )).single['label'],
        'Local tag label',
      );
      expect(
        (await fixture.database.database.query(
          'reference_data',
          where: 'id = ?',
          whereArgs: ['user.reference.merge'],
        )).single['code'],
        'local-reference',
      );
      expect(
        (await fixture.database.database.query(
          'reference_data_translations',
          where: 'reference_data_id = ? AND locale = ?',
          whereArgs: ['user.reference.merge', 'en'],
        )).single['label'],
        'Local reference label',
      );
    },
  );

  test('merge retains newer local budget values', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2026, 1, 1).toIso8601String();
    await fixture.database.database.insert('budgets', {
      'id': 'budget-overall',
      'scope': 'overall',
      'scope_id': null,
      'currency': 'USD',
      'amount': '1000',
      'created_at': old,
      'updated_at': old,
    });
    final backup = File(
      path.join(fixture.root.path, 'budget-merge.butlerlybackup'),
    );
    await fixture.backups.createBackup(backup);
    final newer = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .toIso8601String();
    await fixture.database.database.update(
      'budgets',
      {'amount': '1200', 'updated_at': newer},
      where: 'id = ?',
      whereArgs: ['budget-overall'],
    );

    final inspection = await fixture.backups.inspect(backup);
    expect(inspection.hasNewerLocalData, isTrue);

    await fixture.backups.restore(backup, mode: LocalRestoreMode.merge);

    final rows = await fixture.database.database.query(
      'budgets',
      where: 'id = ?',
      whereArgs: ['budget-overall'],
    );
    expect(rows.single['amount'], '1200');
  });

  test(
    'replace inspection warns about divergent values with old timestamps',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final old = DateTime.utc(2026, 1, 1);
      await fixture.database.database.insert('budgets', {
        'id': 'budget-divergent',
        'scope': 'overall',
        'scope_id': null,
        'currency': 'USD',
        'amount': '1000',
        'created_at': old.toIso8601String(),
        'updated_at': old.toIso8601String(),
      });
      await fixture.insertTransaction(
        id: 'transaction-divergent',
        description: 'Backup description',
        updatedAt: old,
      );
      final backup = File(
        path.join(fixture.root.path, 'divergent-values.butlerlybackup'),
      );
      await fixture.backups.createBackup(backup);
      await fixture.database.database.update(
        'budgets',
        {'amount': '1200'},
        where: 'id = ?',
        whereArgs: ['budget-divergent'],
      );
      await fixture.database.database.update(
        'transactions',
        {'description': 'Local description'},
        where: 'id = ?',
        whereArgs: ['transaction-divergent'],
      );

      final inspection = await fixture.backups.inspect(backup);
      expect(inspection.changes.masterDataChanged, greaterThanOrEqualTo(1));
      expect(inspection.changes.transactionsChanged, greaterThanOrEqualTo(1));
      expect(inspection.hasNewerLocalData, isTrue);
    },
  );

  test(
    'inspection ignores generated workflow rows omitted from the backup',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction(
        id: 'tx-generated-inspection',
        description: 'generated inspection transaction',
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      const now = '2026-10-01T00:00:00.000Z';
      await fixture.database.database.insert('provenances', {
        'id': 'prov-generated-inspection',
        'source_type': 'manual',
        'captured_at': now,
      });
      final backup = File(
        path.join(fixture.root.path, 'generated-inspection.butlerly'),
      );
      await fixture.backups.createBackup(backup);
      await fixture.database.database.insert('review_issues', {
        'id': 'review-generated-inspection',
        'transaction_id': 'tx-generated-inspection',
        'reason': 'generated',
        'status': 'open',
        'created_at': now,
      });
      await fixture.database.database.insert('suggestions', {
        'id': 'suggestion-generated-inspection',
        'transaction_id': 'tx-generated-inspection',
        'target': 'category',
        'proposed_value': 'category.food',
        'method': 'local',
        'status': 'proposed',
        'provenance_id': 'prov-generated-inspection',
        'created_at': now,
      });
      await fixture.database.database.insert('reconciliation_candidates', {
        'id': 'candidate-generated-inspection',
        'receipt_transaction_id': 'tx-generated-inspection',
        'payment_transaction_id': 'tx-generated-inspection',
        'score': 0.5,
        'reasons_json': '[]',
        'status': 'proposed',
        'created_at': now,
        'updated_at': now,
      });

      final inspection = await fixture.backups.inspect(backup);

      expect(inspection.hasNewerLocalData, isFalse);
      expect(inspection.changes.masterDataChanged, 0);
      expect(inspection.changes.deletedEntities, 0);
    },
  );

  test('replace inspection warns about local-only catalog children', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    const timestamp = '2026-10-01T00:00:00.000Z';
    await fixture.database.database.insert('categories', {
      'id': 'user.category.local-only',
      'name': 'Local-only category',
      'origin': 'user',
      'parent_id': null,
      'status': 'active',
      'created_at': timestamp,
      'updated_at': timestamp,
    });
    await fixture.database.database.insert('category_translations', {
      'category_id': 'user.category.local-only',
      'locale': 'en',
      'label': 'Backed-up label',
    });
    final backup = File(
      path.join(fixture.root.path, 'local-only-child.butlerlybackup'),
    );
    await fixture.backups.createBackup(backup);
    await fixture.database.database.insert('category_translations', {
      'category_id': 'user.category.local-only',
      'locale': 'fr',
      'label': 'Local-only label',
    });

    final inspection = await fixture.backups.inspect(backup);
    expect(inspection.hasNewerLocalData, isTrue);

    await fixture.backups.restore(backup, mode: LocalRestoreMode.replace);

    expect(
      await fixture.database.database.query(
        'category_translations',
        where: 'category_id = ? AND locale = ?',
        whereArgs: ['user.category.local-only', 'fr'],
      ),
      isEmpty,
    );
  });

  test('replace inspection warns about local-only master records', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final backup = File(
      path.join(fixture.root.path, 'local-only-master.butlerlybackup'),
    );
    await fixture.backups.createBackup(backup);
    const old = '2020-01-01T00:00:00.000Z';
    await fixture.database.database.insert('categories', {
      'id': 'user.category.only-master',
      'name': 'Only local category',
      'origin': 'user',
      'parent_id': null,
      'status': 'active',
      'created_at': old,
      'updated_at': old,
    });
    await fixture.database.database.insert('merchants', {
      'id': 'user.merchant.only-master',
      'name': 'Only local merchant',
      'status': 'active',
      'normalized_name': 'only local merchant',
      'is_built_in': 0,
      'created_at': old,
      'updated_at': old,
    });
    await fixture.database.database.insert('tags', {
      'id': 'user.tag.only-master',
      'name': 'Only local tag',
      'status': 'active',
      'created_at': old,
      'updated_at': old,
    });
    await fixture.database.database.insert('payment_sources', {
      'id': 'only-local-source',
      'name': 'Only local source',
      'type': 'card',
      'status': 'active',
      'created_at': old,
      'updated_at': old,
    });
    await fixture.database.database.insert('budgets', {
      'id': 'only-local-budget',
      'scope': 'overall',
      'scope_id': null,
      'currency': 'USD',
      'amount': '300.00',
      'created_at': old,
      'updated_at': old,
    });

    final inspection = await fixture.backups.inspect(backup);
    expect(inspection.changes.masterDataChanged, greaterThanOrEqualTo(5));
    expect(inspection.hasNewerLocalData, isTrue);
  });

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
      {
        'description': 'New local value',
        'updated_at': future.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: ['keep-local'],
    );
    await fixture.database.database.update(
      'transactions',
      {
        'description': 'Stale local value',
        'updated_at': oldTime.toIso8601String(),
      },
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

  test(
    'merge applies backup deletion tombstone unless local row is newer',
    () async {
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
      final backup = File(
        path.join(fixture.root.path, 'deleted.butlerlybackup'),
      );
      await fixture.backups.createBackup(backup);

      await fixture.insertTransaction(
        id: 'deleted-at-source',
        description: 'Old local copy',
        updatedAt: oldTime,
      );
      await fixture.backups.restore(backup, mode: LocalRestoreMode.merge);
      expect(await fixture.description('deleted-at-source'), isNull);
    },
  );

  test('backup restores checksum-protected evidence in merge mode', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final evidence = File(path.join(fixture.evidence.path, 'receipt.bin'));
    await evidence.writeAsBytes([1, 2, 3, 4]);
    final backup = File(
      path.join(fixture.root.path, 'evidence.butlerlybackup'),
    );
    await fixture.backups.createBackup(backup);
    await evidence.delete();

    await fixture.backups.restore(backup, mode: LocalRestoreMode.merge);

    expect(await evidence.readAsBytes(), [1, 2, 3, 4]);
  });

  test('backup and replace restore payment settlements', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final oldTime = DateTime.utc(2026, 1, 1);

    await fixture.insertPaymentSource(id: 'visa', name: 'Visa');
    await fixture.insertPaymentSettlement(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      updatedAt: oldTime,
    );
    final backup = File(
      path.join(fixture.root.path, 'settlement.butlerlybackup'),
    );
    await fixture.backups.createBackup(backup);

    await fixture.database.database.delete(
      'payment_settlements',
      where: 'id = ?',
      whereArgs: ['settlement-1'],
    );

    await fixture.backups.restore(backup, mode: LocalRestoreMode.replace);

    expect(await fixture.settlementStatus('settlement-1'), 'open');
  });

  test('merge keeps a newer local payment settlement', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final oldTime = DateTime.utc(2026, 1, 1);

    await fixture.insertPaymentSource(id: 'visa', name: 'Visa');
    await fixture.insertPaymentSettlement(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      updatedAt: oldTime,
      status: 'open',
    );
    final backup = File(
      path.join(fixture.root.path, 'settlement-merge.butlerlybackup'),
    );
    await fixture.backups.createBackup(backup);

    final newer = DateTime.now().toUtc().add(const Duration(minutes: 5));
    await fixture.database.database.update(
      'payment_settlements',
      {'status': 'reconciled', 'updated_at': newer.toIso8601String()},
      where: 'id = ?',
      whereArgs: ['settlement-1'],
    );

    await fixture.backups.restore(backup, mode: LocalRestoreMode.merge);

    expect(await fixture.settlementStatus('settlement-1'), 'reconciled');
  });

  test('replace accepts a v8 backup without payment settlements', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final oldTime = DateTime.utc(2026, 1, 1);

    await fixture.insertPaymentSource(id: 'visa', name: 'Visa');
    final backup = File(
      path.join(fixture.root.path, 'legacy-v8.butlerlybackup'),
    );
    await fixture.backups.createBackup(backup);
    await _downgradeBackupToV8(backup);

    await fixture.database.database.insert('reference_data', {
      'id': 'user.reference.legacy-stale',
      'code': 'legacy-stale',
      'type': 'legacy-test',
      'origin': 'user',
      'status': 'active',
    });
    await fixture.database.database.insert('reference_data_translations', {
      'reference_data_id': 'user.reference.legacy-stale',
      'locale': 'en',
      'label': 'Legacy stale reference',
    });

    await fixture.insertPaymentSettlement(
      id: 'local-v9-settlement',
      paymentSourceId: 'visa',
      updatedAt: oldTime,
    );

    await fixture.backups.restore(backup, mode: LocalRestoreMode.replace);

    expect(await fixture.settlementStatus('local-v9-settlement'), isNull);
    expect(
      await fixture.database.database.query(
        'reference_data',
        where: 'id = ?',
        whereArgs: ['user.reference.legacy-stale'],
      ),
      isEmpty,
    );
  });

  test(
    'replace migrates a v9 settlement backup without restoring its legacy transfer',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final oldTime = DateTime.utc(2026, 1, 1);

      await fixture.insertPaymentSource(id: 'visa', name: 'Visa');
      await fixture.insertPaymentSettlement(
        id: 'settlement-1',
        paymentSourceId: 'visa',
        updatedAt: oldTime,
      );
      final backup = File(
        path.join(fixture.root.path, 'legacy-v9.butlerlybackup'),
      );
      await fixture.backups.createBackup(backup);
      await _downgradeBackupToV9(backup);

      await fixture.database.database.delete('payment_settlements');
      await fixture.backups.restore(backup, mode: LocalRestoreMode.replace);

      expect(await fixture.settlementStatus('settlement-1'), 'open');
      expect(
        await fixture.database.database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['legacy-payment-settlement-1'],
        ),
        isEmpty,
      );
      final row = (await fixture.database.database.query(
        'payment_settlements',
        where: 'id = ?',
        whereArgs: ['settlement-1'],
      )).single;
      expect(row['payment_amount_coefficient'], '284672');
      expect(row['payment_currency'], 'USD');
      expect(row['payment_date'], '2026-09-20');
      expect(
        await fixture.database.database.query('reconciliation_candidates'),
        isEmpty,
      );
      expect(
        await fixture.database.database.query('reconciliation_links'),
        isEmpty,
      );
      final statementRow = (await fixture.database.database.query(
        'statement_rows',
        where: 'id = ?',
        whereArgs: ['legacy-statement-row'],
      )).single;
      expect(statementRow['transaction_id'], isNull);
    },
  );

  test('merge applies a payment settlement deletion tombstone', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final oldTime = DateTime.utc(2026, 1, 1);

    await fixture.insertPaymentSource(id: 'visa', name: 'Visa');
    await fixture.insertPaymentSettlement(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      updatedAt: oldTime,
    );
    await fixture.database.database.delete(
      'payment_settlements',
      where: 'id = ?',
      whereArgs: ['settlement-1'],
    );
    final backup = File(
      path.join(fixture.root.path, 'settlement-delete.butlerlybackup'),
    );
    await fixture.backups.createBackup(backup);

    await fixture.insertPaymentSettlement(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      updatedAt: oldTime,
    );

    await fixture.backups.restore(backup, mode: LocalRestoreMode.merge);

    expect(await fixture.settlementStatus('settlement-1'), isNull);
  });
}

Future<void> _downgradeBackupToV9(File backup) async {
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
  manifest['schemaVersion'] = 9;

  final settlements = (tables['payment_settlements']! as List)
      .cast<Map>()
      .map((row) => row.cast<String, Object?>())
      .toList();
  final transactions = (tables['transactions']! as List)
      .cast<Map>()
      .map((row) => row.cast<String, Object?>())
      .toList();
  for (final settlement in settlements) {
    final transactionId = 'legacy-payment-${settlement['id']}';
    transactions.add({
      'id': transactionId,
      'amount_coefficient': settlement.remove('payment_amount_coefficient'),
      'amount_scale': settlement.remove('payment_amount_scale'),
      'currency': settlement.remove('payment_currency'),
      'transaction_date': settlement.remove('payment_date'),
      'direction': 'transfer',
      'status': 'active',
      'payment_source_id': settlement['payment_source_id'],
      'created_at': settlement['created_at'],
      'updated_at': settlement['updated_at'],
    });
    settlement['settlement_transaction_id'] = transactionId;
  }
  tables['payment_settlements'] = settlements;
  transactions.add({
    'id': 'legacy-receipt',
    'amount_coefficient': '284672',
    'amount_scale': 2,
    'currency': 'USD',
    'direction': 'expense',
    'source_type': 'manual',
    'status': 'active',
    'payment_source_id': 'visa',
    'transaction_date': '2026-09-10',
    'unknown_time_reason': 'unknown',
    'created_at': '2026-09-10T12:00:00.000Z',
    'updated_at': '2026-09-10T12:00:00.000Z',
  });
  tables['transactions'] = transactions;

  final legacyPaymentId = 'legacy-payment-settlement-1';
  (tables['provenances']! as List).add({
    'id': 'legacy-statement-provenance',
    'source_type': 'import',
    'captured_at': '2026-09-10T12:00:00.000Z',
  });
  (tables['evidence_items']! as List).add({
    'id': 'legacy-statement-evidence',
    'type': 'statement',
    'original_name': 'legacy.pdf',
    'media_type': 'application/pdf',
    'provenance_id': 'legacy-statement-provenance',
    'created_at': '2026-09-10T12:00:00.000Z',
  });
  (tables['financial_statements']! as List).add({
    'id': 'legacy-statement',
    'evidence_id': 'legacy-statement-evidence',
    'payment_source_id': 'visa',
    'status': 'processed',
    'created_at': '2026-09-10T12:00:00.000Z',
    'updated_at': '2026-09-10T12:00:00.000Z',
  });
  (tables['statement_rows']! as List).add({
    'id': 'legacy-statement-row',
    'statement_id': 'legacy-statement',
    'position': 0,
    'original_text': 'Card payment',
    'row_kind': 'transaction',
    'status': 'linked',
    'transaction_id': legacyPaymentId,
    'created_at': '2026-09-10T12:00:00.000Z',
    'updated_at': '2026-09-10T12:00:00.000Z',
  });
  (tables['reconciliation_candidates']! as List).add({
    'id': 'legacy-candidate',
    'receipt_transaction_id': 'legacy-receipt',
    'payment_transaction_id': legacyPaymentId,
    'score': 1.0,
    'reasons_json': '[]',
    'status': 'confirmed',
    'created_at': '2026-09-20T12:00:00.000Z',
    'updated_at': '2026-09-20T12:00:00.000Z',
  });
  (tables['reconciliation_links']! as List).add({
    'id': 'legacy-link',
    'candidate_id': 'legacy-candidate',
    'receipt_transaction_id': 'legacy-receipt',
    'payment_transaction_id': legacyPaymentId,
    'created_at': '2026-09-20T12:00:00.000Z',
  });

  final encoded = utf8.encode(jsonEncode(metadata));
  final output = <int>[
    ...magic,
    ...int64Bytes(encoded.length),
    ...ascii.encode(sha256Bytes(encoded)),
    ...encoded,
    ...bytes.sublist(metadataEnd),
  ];
  await backup.writeAsBytes(output, flush: true);
}

Future<void> _downgradeBackupToV8(File backup) async {
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
  manifest['schemaVersion'] = 8;
  tables.remove('payment_settlements');
  tables.remove('reference_data');
  tables.remove('reference_data_translations');

  final encoded = utf8.encode(jsonEncode(metadata));
  final output = <int>[
    ...magic,
    ...int64Bytes(encoded.length),
    ...ascii.encode(sha256Bytes(encoded)),
    ...encoded,
    ...bytes.sublist(metadataEnd),
  ];
  await backup.writeAsBytes(output, flush: true);
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

  Future<void> insertPaymentSource({
    required String id,
    required String name,
  }) async {
    await database.database.insert('payment_sources', {
      'id': id,
      'name': name,
      'type': 'card',
      'status': 'active',
    });
  }

  Future<void> insertPaymentSettlement({
    required String id,
    required String paymentSourceId,
    required DateTime updatedAt,
    String status = 'open',
  }) async {
    await database.database.insert('payment_settlements', {
      'id': id,
      'payment_source_id': paymentSourceId,
      'payment_amount_coefficient': '284672',
      'payment_amount_scale': 2,
      'payment_currency': 'USD',
      'payment_date': '2026-09-20',
      'period_start': '2026-08-15',
      'period_end': '2026-09-14',
      'status': status,
      'created_at': updatedAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    });
  }

  Future<String?> settlementStatus(String id) async {
    final rows = await database.database.query(
      'payment_settlements',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['status'] as String?;
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
