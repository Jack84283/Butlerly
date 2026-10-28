import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_backup_engine.dart' as engine;
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
    expect(manifest['schemaVersion'], 15);
  });

  test('backup and restore preserves the optional financial profile', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.database.database.insert('financial_profiles', {
      'profile_id': 'financial-profile:default',
      'schema_version': 1,
      'survey_version': '1.0',
      'household_size': 'two',
      'dependents_count': null,
      'housing_situation': null,
      'primary_spending_categories': '["category.food"]',
      'expense_predictability': null,
      'categories_to_improve': '[]',
      'primary_financial_goal': 'saveMore',
      'has_monthly_savings_target': 0,
      'monthly_savings_target': null,
      'monthly_savings_target_currency': null,
      'goal_timeframe': null,
      'budgeting_preference': null,
      'preferred_insight_types': '["spendingTrends"]',
      'survey_status': 'inProgress',
      'created_at': '2026-10-28T00:00:00.000Z',
      'updated_at': '2026-10-28T00:00:00.000Z',
      'completed_at': null,
    });
    final backup = File(
      path.join(fixture.root.path, 'financial-profile.butlerlybackup'),
    );

    await fixture.manager.createBackup(backup);
    await fixture.database.database.delete('financial_profiles');
    await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

    final restored = await fixture.database.database.query(
      'financial_profiles',
    );
    expect(restored.single['household_size'], 'two');
    expect(restored.single['has_monthly_savings_target'], 0);
    expect(restored.single['preferred_insight_types'], '["spendingTrends"]');
  });

  test('merge restore preserves a newer local financial profile', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.database.database.insert('financial_profiles', {
      'profile_id': 'financial-profile:default',
      'schema_version': 1,
      'survey_version': '1.0',
      'household_size': 'two',
      'dependents_count': null,
      'housing_situation': null,
      'primary_spending_categories': '[]',
      'expense_predictability': null,
      'categories_to_improve': '[]',
      'primary_financial_goal': null,
      'has_monthly_savings_target': null,
      'monthly_savings_target': null,
      'monthly_savings_target_currency': null,
      'goal_timeframe': null,
      'budgeting_preference': null,
      'preferred_insight_types': '[]',
      'survey_status': 'inProgress',
      'created_at': '2026-10-28T00:00:00.000Z',
      'updated_at': '2026-10-28T00:00:00.000Z',
      'completed_at': null,
    });
    final backup = File(
      path.join(fixture.root.path, 'financial-profile-merge.butlerlybackup'),
    );
    await fixture.manager.createBackup(backup);

    await fixture.database.database.update(
      'financial_profiles',
      {'household_size': 'four', 'updated_at': '2026-10-29T00:00:00.000Z'},
      where: 'profile_id = ?',
      whereArgs: ['financial-profile:default'],
    );
    await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);

    final restored = await fixture.database.database.query(
      'financial_profiles',
    );
    expect(restored.single['household_size'], 'four');
    expect(restored.single['updated_at'], '2026-10-29T00:00:00.000Z');
  });

  test('restore rejects an unreconstructable financial profile enum', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.database.database.insert('financial_profiles', {
      'profile_id': 'financial-profile:default',
      'schema_version': 1,
      'survey_version': '1.0',
      'household_size': 'two',
      'dependents_count': null,
      'housing_situation': null,
      'primary_spending_categories': '[]',
      'expense_predictability': null,
      'categories_to_improve': '[]',
      'primary_financial_goal': null,
      'has_monthly_savings_target': null,
      'monthly_savings_target': null,
      'monthly_savings_target_currency': null,
      'goal_timeframe': null,
      'budgeting_preference': null,
      'preferred_insight_types': '[]',
      'survey_status': 'inProgress',
      'created_at': '2026-10-28T00:00:00.000Z',
      'updated_at': '2026-10-28T00:00:00.000Z',
      'completed_at': null,
    });
    final backup = File(
      path.join(fixture.root.path, 'invalid-financial-profile.butlerlybackup'),
    );
    await fixture.manager.createBackup(backup);
    await _rewriteBackupMetadata(backup, (metadata) {
      final tables = (metadata['tables']! as Map).cast<String, Object?>();
      final rows = (tables['financial_profiles']! as List).cast<Map>();
      rows.single['household_size'] = 'unknown';
    });

    await expectLater(
      fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
      throwsA(isA<FormatException>()),
    );
    final preserved = await fixture.database.database.query(
      'financial_profiles',
    );
    expect(preserved.single['household_size'], 'two');
  });

  test('restore rejects malformed financial profile answer lists', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.database.database.insert('financial_profiles', {
      'profile_id': 'financial-profile:default',
      'schema_version': 1,
      'survey_version': '1.0',
      'household_size': null,
      'dependents_count': null,
      'housing_situation': null,
      'primary_spending_categories': '[]',
      'expense_predictability': null,
      'categories_to_improve': '[]',
      'primary_financial_goal': null,
      'has_monthly_savings_target': null,
      'monthly_savings_target': null,
      'monthly_savings_target_currency': null,
      'goal_timeframe': null,
      'budgeting_preference': null,
      'preferred_insight_types': '[]',
      'survey_status': 'notStarted',
      'created_at': '2026-10-28T00:00:00.000Z',
      'updated_at': '2026-10-28T00:00:00.000Z',
      'completed_at': null,
    });
    final backup = File(
      path.join(
        fixture.root.path,
        'invalid-financial-profile-list.butlerlybackup',
      ),
    );
    await fixture.manager.createBackup(backup);
    await _rewriteBackupMetadata(backup, (metadata) {
      final tables = (metadata['tables']! as Map).cast<String, Object?>();
      final rows = (tables['financial_profiles']! as List).cast<Map>();
      rows.single['primary_spending_categories'] =
          '["category.one","category.two","category.three","category.four"]';
    });

    await expectLater(
      fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
      throwsA(isA<FormatException>()),
    );
    final preserved = await fixture.database.database.query(
      'financial_profiles',
    );
    expect(preserved.single['primary_spending_categories'], '[]');
  });

  test(
    'current-schema backups reject missing tables before replacing local data',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.database.database.insert('budgets', {
        'id': 'budget-preserve-on-rejection',
        'scope': 'overall',
        'scope_id': null,
        'currency': 'USD',
        'amount': '500.00',
        'created_at': '2026-10-01T00:00:00.000Z',
        'updated_at': '2026-10-01T00:00:00.000Z',
      });
      final backup = File(
        path.join(fixture.root.path, 'incomplete-current-schema.butlerly'),
      );
      await fixture.manager.createBackup(backup);
      await _removeTableFromBackup(backup, 'budgets');

      await expectLater(
        fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );
      expect(
        await fixture.database.database.query(
          'budgets',
          where: 'id = ?',
          whereArgs: ['budget-preserve-on-rejection'],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'restore rejects missing referenced evidence before activating the package',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-evidence-preserve');
      await fixture.database.database.insert('evidence_items', {
        'id': 'evidence-preserve',
        'type': 'receipt',
        'original_name': 'receipt.bin',
        'media_type': 'application/octet-stream',
        'provenance_id': 'tx-evidence-preserve-provenance',
        'created_at': '2026-09-01T00:00:00.000Z',
        'local_file_name': 'receipt.bin',
      });
      final liveEvidence = File(
        path.join(fixture.evidence.path, 'receipt.bin'),
      );
      await liveEvidence.writeAsString('live evidence', flush: true);
      final backup = File(
        path.join(fixture.root.path, 'missing-evidence-reference.butlerly'),
      );
      await fixture.manager.createBackup(backup);
      await _rewriteBackupMetadata(backup, (metadata) {
        final tables = (metadata['tables']! as Map).cast<String, Object?>();
        final rows = (tables['evidence_items']! as List).cast<Map>();
        rows.single['local_file_name'] = 'missing.bin';
      });

      await expectLater(
        fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );
      expect(await liveEvidence.readAsString(), 'live evidence');
      expect(
        await fixture.database.database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['tx-evidence-preserve'],
        ),
        hasLength(1),
      );
      final stagingDirectories = await fixture.evidence.parent
          .list(followLinks: false)
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .where(
            (directory) =>
                path.basename(directory.path).startsWith('evidence.restore-'),
          )
          .toList();
      expect(stagingDirectories, isEmpty);

      for (final invalidReference in <Object?>[
        '../receipt.bin',
        r'..\receipt.bin',
        42,
      ]) {
        await fixture.manager.createBackup(backup);
        await _rewriteBackupMetadata(backup, (metadata) {
          final tables = (metadata['tables']! as Map).cast<String, Object?>();
          final rows = (tables['evidence_items']! as List).cast<Map>();
          rows.single['local_file_name'] = invalidReference;
        });
        await expectLater(
          fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
          throwsA(isA<FormatException>()),
        );
        expect(fixture.manager.recoveryState.isRecoveryRequired, isFalse);
      }
    },
  );

  test(
    'restore rejects malformed budget scope references before mutation',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.database.database.insert('budgets', {
        'id': 'budget-invalid-scope',
        'scope': 'overall',
        'scope_id': null,
        'currency': 'USD',
        'amount': '100.00',
        'created_at': '2026-10-01T00:00:00.000Z',
        'updated_at': '2026-10-01T00:00:00.000Z',
      });
      final backup = File(
        path.join(fixture.root.path, 'invalid-budget-scope.butlerlybackup'),
      );
      await fixture.manager.createBackup(backup);

      for (final invalidScopeId in <Object?>['missing-category', 42]) {
        await fixture.manager.createBackup(backup);
        await _rewriteBackupMetadata(backup, (metadata) {
          final tables = (metadata['tables']! as Map).cast<String, Object?>();
          final rows = (tables['budgets']! as List).cast<Map>();
          rows.single['scope'] = 'category';
          rows.single['scope_id'] = invalidScopeId;
        });

        await expectLater(
          fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
          throwsA(isA<FormatException>()),
        );
        expect(
          await fixture.database.database.query(
            'budgets',
            where: 'id = ?',
            whereArgs: ['budget-invalid-scope'],
          ),
          hasLength(1),
        );
      }
    },
  );

  test(
    'restore rejects duplicate normalized evidence paths before mutation',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-duplicate-evidence-path');
      await fixture.database.database.insert('evidence_items', {
        'id': 'evidence-one',
        'type': 'receipt',
        'original_name': 'one.bin',
        'media_type': 'application/octet-stream',
        'provenance_id': 'tx-duplicate-evidence-path-provenance',
        'created_at': '2026-09-01T00:00:00.000Z',
        'local_file_name': 'one.bin',
      });
      await fixture.database.database.insert('evidence_items', {
        'id': 'evidence-two',
        'type': 'receipt',
        'original_name': 'two.bin',
        'media_type': 'application/octet-stream',
        'provenance_id': 'tx-duplicate-evidence-path-provenance',
        'created_at': '2026-09-01T00:00:00.000Z',
        'local_file_name': 'two.bin',
      });
      await File(
        path.join(fixture.evidence.path, 'one.bin'),
      ).writeAsString('one');
      await File(
        path.join(fixture.evidence.path, 'two.bin'),
      ).writeAsString('two');
      final backup = File(
        path.join(fixture.root.path, 'duplicate-evidence-path.butlerlybackup'),
      );
      await fixture.manager.createBackup(backup);
      await fixture.database.database.update(
        'transactions',
        {'description': 'local edit'},
        where: 'id = ?',
        whereArgs: ['tx-duplicate-evidence-path'],
      );
      await _rewriteBackupMetadata(backup, (metadata) {
        final evidence = (metadata['evidence']! as List).cast<Map>();
        expect(evidence, hasLength(2));
        evidence[1]['path'] = './${evidence[0]['path']}';
      });

      await expectLater(
        fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );
      expect(
        (await fixture.database.database.query(
          'transactions',
          columns: ['description'],
          where: 'id = ?',
          whereArgs: ['tx-duplicate-evidence-path'],
        )).single['description'],
        'local edit',
      );
      expect(
        await File(path.join(fixture.evidence.path, 'one.bin')).readAsString(),
        'one',
      );
      expect(
        await File(path.join(fixture.evidence.path, 'two.bin')).readAsString(),
        'two',
      );

      await fixture.manager.createBackup(backup);
      await _rewriteBackupMetadata(backup, (metadata) {
        final evidence = (metadata['evidence']! as List).cast<Map>();
        evidence[1]['path'] = (evidence[0]['path']! as String).toUpperCase();
      });
      await expectLater(
        fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );

      await fixture.manager.createBackup(backup);
      await _rewriteBackupMetadata(backup, (metadata) {
        final evidence = (metadata['evidence']! as List).cast<Map>();
        evidence.first['path'] = r'..\outside.bin';
      });
      await expectLater(
        fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'restore writes nested user categories in parent-before-child order',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      const timestamp = '2026-10-01T00:00:00.000Z';
      await fixture.database.database.insert('categories', {
        'id': 'z-category-parent',
        'name': 'Parent',
        'origin': 'user',
        'parent_id': null,
        'status': 'active',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await fixture.database.database.insert('categories', {
        'id': 'a-category-child',
        'name': 'Child',
        'origin': 'user',
        'parent_id': 'z-category-parent',
        'status': 'active',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await fixture.database.database.insert('categories', {
        'id': 'a-category-grandchild',
        'name': 'Grandchild',
        'origin': 'user',
        'parent_id': 'a-category-child',
        'status': 'active',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      final backup = File(
        path.join(fixture.root.path, 'nested-categories.butlerly'),
      );
      await fixture.manager.createBackup(backup);
      await fixture.database.database.delete(
        'categories',
        where: 'id = ?',
        whereArgs: ['a-category-grandchild'],
      );
      await fixture.database.database.delete(
        'categories',
        where: 'id = ?',
        whereArgs: ['a-category-child'],
      );
      await fixture.database.database.delete(
        'categories',
        where: 'id = ?',
        whereArgs: ['z-category-parent'],
      );

      await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

      final child = await fixture.database.database.query(
        'categories',
        where: 'id = ?',
        whereArgs: ['a-category-child'],
      );
      expect(child.single['parent_id'], 'z-category-parent');
      final grandchild = await fixture.database.database.query(
        'categories',
        where: 'id = ?',
        whereArgs: ['a-category-grandchild'],
      );
      expect(grandchild.single['parent_id'], 'a-category-child');
    },
  );

  test('restore preserves references to omitted system catalog rows', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.insertTransaction('tx-system-catalog-reference');
    await fixture.database.database.update(
      'transactions',
      {
        'merchant_id': 'merchant.safeway',
        'category_id': 'category.food.groceries',
      },
      where: 'id = ?',
      whereArgs: ['tx-system-catalog-reference'],
    );
    final backup = File(
      path.join(fixture.root.path, 'system-catalog-reference.butlerly'),
    );
    await fixture.manager.createBackup(backup);
    await fixture.database.database.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: ['tx-system-catalog-reference'],
    );

    await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

    final row = (await fixture.database.database.query(
      'transactions',
      where: 'id = ?',
      whereArgs: ['tx-system-catalog-reference'],
    )).single;
    expect(row['merchant_id'], 'merchant.safeway');
    expect(row['category_id'], 'category.food.groceries');
  });

  test(
    'new builds restore schema 13 backups without V1 child tables',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-schema-13');
      final backup = File(
        path.join(fixture.root.path, 'schema-13.butlerlybackup'),
      );
      await fixture.manager.createBackup(backup);
      await _downgradeBackupToV13(backup);

      await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

      expect(await _ids(fixture, 'transactions'), contains('tx-schema-13'));
    },
  );

  test(
    'new builds restore historical schema 13 payloads without budgets',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final backup = File(
        path.join(fixture.root.path, 'historical-schema-13.butlerlybackup'),
      );
      await _writeHistoricalSchema13Backup(backup);

      await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

      expect(
        await _ids(fixture, 'transactions'),
        contains('historical-schema-13'),
      );
      expect(
        engine.LocalBackupManager.requiredTablesForSchema(13),
        isNot(contains('budgets')),
      );
      expect(
        engine.LocalBackupManager.requiredTablesForSchema(14),
        contains('budgets'),
      );
      expect(
        engine.LocalBackupManager.requiredTablesForSchema(14),
        isNot(contains('financial_profiles')),
      );
      expect(
        engine.LocalBackupManager.requiredTablesForSchema(15),
        contains('financial_profiles'),
      );
    },
  );

  test(
    'schema 14 rejects null and malformed required table payloads before mutation',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-malformed-payload');
      await fixture.database.database.insert('budgets', {
        'id': 'budget-malformed-payload',
        'scope': 'overall',
        'scope_id': null,
        'currency': 'USD',
        'amount': '500.00',
        'created_at': '2026-10-01T00:00:00.000Z',
        'updated_at': '2026-10-01T00:00:00.000Z',
      });

      final cases = <String, Object?>{'transactions': null, 'budgets': null};
      for (final entry in cases.entries) {
        final backup = File(
          path.join(fixture.root.path, 'malformed-${entry.key}.butlerly'),
        );
        await fixture.manager.createBackup(backup);
        await _rewriteBackupMetadata(backup, (metadata) {
          final tables = (metadata['tables']! as Map).cast<String, Object?>();
          tables[entry.key] = entry.value;
        });

        await expectLater(
          fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
          throwsA(isA<FormatException>()),
        );
        expect(
          await fixture.database.database.query(
            'transactions',
            where: 'id = ?',
            whereArgs: ['tx-malformed-payload'],
          ),
          hasLength(1),
        );
        expect(
          await fixture.database.database.query(
            'budgets',
            where: 'id = ?',
            whereArgs: ['budget-malformed-payload'],
          ),
          hasLength(1),
        );
      }

      final malformedRow = File(
        path.join(fixture.root.path, 'malformed-row.butlerly'),
      );
      await fixture.manager.createBackup(malformedRow);
      await _rewriteBackupMetadata(malformedRow, (metadata) {
        final tables = (metadata['tables']! as Map).cast<String, Object?>();
        tables['transactions'] = [
          <String, Object?>{'description': 'missing transaction identity'},
        ];
      });
      await expectLater(
        fixture.manager.restore(malformedRow, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );
      expect(
        await fixture.database.database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['tx-malformed-payload'],
        ),
        hasLength(1),
      );

      final duplicateRows = File(
        path.join(fixture.root.path, 'duplicate-identity.butlerly'),
      );
      await fixture.manager.createBackup(duplicateRows);
      await _rewriteBackupMetadata(duplicateRows, (metadata) {
        final tables = (metadata['tables']! as Map).cast<String, Object?>();
        final budgets = (tables['budgets']! as List).cast<Map>();
        final original = budgets.single.cast<String, Object?>();
        tables['budgets'] = [
          original,
          <String, Object?>{...original, 'amount': '900.00'},
        ];
      });
      await expectLater(
        fixture.manager.restore(duplicateRows, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );
      expect(
        await fixture.database.database.query(
          'budgets',
          where: 'id = ?',
          whereArgs: ['budget-malformed-payload'],
        ),
        hasLength(1),
      );

      final unknownTable = File(
        path.join(fixture.root.path, 'unknown-table.butlerly'),
      );
      await fixture.manager.createBackup(unknownTable);
      await _rewriteBackupMetadata(unknownTable, (metadata) {
        final tables = (metadata['tables']! as Map).cast<String, Object?>();
        tables['future_table'] = <Object?>[];
      });
      await expectLater(
        fixture.manager.restore(unknownTable, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'restore rejects partial merchant and transaction rows before merge',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-partial-row');
      final merchantBackup = File(
        path.join(fixture.root.path, 'partial-merchant.butlerly'),
      );
      await fixture.manager.createBackup(merchantBackup);
      await _rewriteBackupMetadata(merchantBackup, (metadata) {
        final tables = (metadata['tables']! as Map).cast<String, Object?>();
        tables['merchants'] = [
          <String, Object?>{
            'id': 'merchant.safeway',
            'name': 'Tampered built-in merchant',
          },
        ];
      });
      await expectLater(
        fixture.manager.restore(merchantBackup, mode: LocalRestoreMode.merge),
        throwsA(isA<FormatException>()),
      );
      final merchant = (await fixture.database.database.query(
        'merchants',
        where: 'id = ?',
        whereArgs: ['merchant.safeway'],
      )).single;
      expect(merchant['name'], 'Safeway');

      final transactionBackup = File(
        path.join(fixture.root.path, 'partial-transaction.butlerly'),
      );
      await fixture.manager.createBackup(transactionBackup);
      await _rewriteBackupMetadata(transactionBackup, (metadata) {
        final tables = (metadata['tables']! as Map).cast<String, Object?>();
        tables['transactions'] = [
          <String, Object?>{
            'id': 'tx-partial-row',
            'amount_coefficient': '999999',
          },
        ];
      });
      await expectLater(
        fixture.manager.restore(
          transactionBackup,
          mode: LocalRestoreMode.merge,
        ),
        throwsA(isA<FormatException>()),
      );
      final transaction = (await fixture.database.database.query(
        'transactions',
        where: 'id = ?',
        whereArgs: ['tx-partial-row'],
      )).single;
      expect(transaction['amount_coefficient'], '100');
    },
  );

  test(
    'restore rejects invalid row values and references before mutation',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-invalid-row-shape');
      final cases = <String, void Function(Map<String, Object?>)>{
        'timestamp': (row) => row['created_at'] = 'not-a-date',
        'decimal': (row) => row['amount_coefficient'] = 'not-a-number',
        'reference': (row) => row['merchant_id'] = 'missing-merchant',
      };

      for (final entry in cases.entries) {
        final backup = File(
          path.join(fixture.root.path, 'invalid-${entry.key}.butlerly'),
        );
        await fixture.manager.createBackup(backup);
        await _rewriteBackupMetadata(backup, (metadata) {
          final tables = (metadata['tables']! as Map).cast<String, Object?>();
          final rows = (tables['transactions']! as List).cast<Map>();
          entry.value(rows.single.cast<String, Object?>());
        });

        await expectLater(
          fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
          throwsA(isA<FormatException>()),
        );
        expect(
          await fixture.database.database.query(
            'transactions',
            where: 'id = ?',
            whereArgs: ['tx-invalid-row-shape'],
          ),
          hasLength(1),
        );
      }
    },
  );

  test(
    'restore rejects invalid transaction enum values before mutation',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-invalid-enum');
      final backup = File(
        path.join(fixture.root.path, 'invalid-enum.butlerlybackup'),
      );
      await fixture.manager.createBackup(backup);
      await _rewriteBackupMetadata(backup, (metadata) {
        final tables = (metadata['tables']! as Map).cast<String, Object?>();
        final rows = (tables['transactions']! as List).cast<Map>();
        rows.single['status'] = 'not-a-status';
      });

      await expectLater(
        fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );
      expect(
        await fixture.database.database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['tx-invalid-enum'],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'restore rejects unknown tombstone types before replacing local data',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-unknown-tombstone');
      final backup = File(
        path.join(fixture.root.path, 'unknown-tombstone.butlerlybackup'),
      );
      await fixture.manager.createBackup(backup);
      await _rewriteBackupMetadata(backup, (metadata) {
        final tables = (metadata['tables']! as Map).cast<String, Object?>();
        final tombstones = (tables['entity_tombstones']! as List).cast<Map>();
        tombstones.add(<String, Object?>{
          'entity_type': 'not-a-table',
          'entity_id': 'tx-unknown-tombstone',
          'deleted_at': '2026-09-01T00:00:00.000Z',
        });
      });

      await expectLater(
        fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );
      expect(
        await fixture.database.database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['tx-unknown-tombstone'],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'merge preserves a newer local tombstone when the entity row is absent',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.insertTransaction('tx-newer-tombstone');
      await fixture.database.database.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: ['tx-newer-tombstone'],
      );
      await fixture.database.database.delete(
        'entity_tombstones',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['transactions', 'tx-newer-tombstone'],
      );
      await fixture.database.database.insert('entity_tombstones', {
        'entity_type': 'transactions',
        'entity_id': 'tx-newer-tombstone',
        'deleted_at': '2026-09-01T00:00:00.000Z',
      });
      final backup = File(
        path.join(fixture.root.path, 'older-tombstone.butlerlybackup'),
      );
      await fixture.manager.createBackup(backup);
      await fixture.database.database.update(
        'entity_tombstones',
        {'deleted_at': '2026-09-02T00:00:00.000Z'},
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['transactions', 'tx-newer-tombstone'],
      );

      await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);

      final tombstone = await fixture.database.database.query(
        'entity_tombstones',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['transactions', 'tx-newer-tombstone'],
      );
      expect(tombstone.single['deleted_at'], '2026-09-02T00:00:00.000Z');
      expect(
        await fixture.database.database.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['tx-newer-tombstone'],
        ),
        isEmpty,
      );
    },
  );

  test('backup rejects symbolic links in the evidence tree', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final outside = File(path.join(fixture.root.path, 'outside.bin'))
      ..writeAsStringSync('private');
    await Link(
      path.join(fixture.evidence.path, 'linked.bin'),
    ).create(outside.path);
    final backup = File(
      path.join(fixture.root.path, 'symlink-evidence.butlerlybackup'),
    );

    await expectLater(
      fixture.manager.createBackup(backup),
      throwsA(isA<FormatException>()),
    );
    expect(await outside.readAsString(), 'private');
  });

  test('backup rejects a symbolic link at the evidence root', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final realEvidence = Directory('${fixture.evidence.path}-real');
    await fixture.evidence.rename(realEvidence.path);
    await Link(fixture.evidence.path).create(realEvidence.path);
    try {
      final backup = File(
        path.join(fixture.root.path, 'symlink-root.butlerlybackup'),
      );
      await expectLater(
        fixture.manager.createBackup(backup),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await Link(fixture.evidence.path).delete();
      await realEvidence.rename(fixture.evidence.path);
    }
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

Future<void> _removeTableFromBackup(File backup, String tableName) async {
  await _rewriteBackupMetadata(backup, (metadata) {
    final tables = (metadata['tables']! as Map).cast<String, Object?>();
    tables.remove(tableName);
  });
}

Future<void> _writeHistoricalSchema13Backup(File backup) async {
  // This is a hand-built payload from the pre-budgets schema-13 format. It is
  // intentionally not produced by creating a current backup and removing a
  // table, so the compatibility test exercises the historical table shape.
  const historicalTables = <String>[
    'payment_sources',
    'payment_settlements',
    'categories',
    'merchants',
    'merchant_aliases',
    'merchant_normalization_patterns',
    'tags',
    'provenances',
    'exchange_rates',
    'transactions',
    'normalized_money',
    'transaction_provenances',
    'transaction_tags',
    'transaction_rules',
    'evidence_items',
    'financial_statements',
    'statement_rows',
    'extractions',
    'attachment_links',
    'suggestions',
    'review_issues',
    'reconciliation_candidates',
    'reconciliation_links',
    'duplicate_candidate_groups',
    'duplicate_candidate_group_transactions',
    'recurring_pattern_decisions',
    'analysis_rule_activations',
    'analysis_rule_configurations',
    'user_preferences',
    'entity_tombstones',
  ];
  final tables = <String, Object?>{
    for (final table in historicalTables) table: <Object?>[],
  };
  tables['transactions'] = [
    <String, Object?>{
      'id': 'historical-schema-13',
      'unknown_time_reason': 'unknown',
      'amount_coefficient': '100',
      'amount_scale': 2,
      'currency': 'USD',
      'direction': 'expense',
      'source_type': 'manual',
      'status': 'active',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    },
  ];
  final metadata = <String, Object?>{
    'manifest': <String, Object?>{
      'format': 'butlerly-backup',
      'formatVersion': 2,
      'schemaVersion': 13,
      'backupId': 'historical-schema-13',
      'appVersion': '1.0.0',
      'appBuild': '1',
      'createdAtUtc': '2026-01-01T00:00:00.000Z',
      'recordCount': 1,
      'evidenceCount': 0,
      'derivedDataPolicy': 'rebuild',
    },
    'tables': tables,
    'evidence': const <Object?>[],
  };
  final encoded = utf8.encode(jsonEncode(metadata));
  await backup.writeAsBytes([
    ...utf8.encode('BUTLERLYBACKUP2'),
    ...int64Bytes(encoded.length),
    ...ascii.encode(sha256Bytes(encoded)),
    ...encoded,
  ], flush: true);
}

Future<void> _rewriteBackupMetadata(
  File backup,
  void Function(Map<String, Object?> metadata) mutate,
) async {
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
  mutate(metadata);
  final encoded = utf8.encode(jsonEncode(metadata));
  await backup.writeAsBytes([
    ...magic,
    ...int64Bytes(encoded.length),
    ...ascii.encode(sha256Bytes(encoded)),
    ...encoded,
    ...bytes.sublist(metadataEnd),
  ], flush: true);
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

Future<void> _downgradeBackupToV13(File backup) async {
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
  manifest['schemaVersion'] = 13;
  for (final table in [
    'category_translations',
    'tag_translations',
    'reference_data',
    'reference_data_translations',
  ]) {
    tables.remove(table);
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
