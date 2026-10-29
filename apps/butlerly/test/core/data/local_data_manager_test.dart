import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('export and erase contracts cover durable user-owned tables', () {
    const derivedTables = {'analysis_findings', 'analysis_rule_results'};
    final exported = LocalDataManager.exportedTableNames.toSet();
    final erased = LocalDataManager.erasedTableNames.where(
      (table) => !derivedTables.contains(table),
    );
    expect(erased.every(exported.contains), isTrue);
    expect(
      exported,
      containsAll(const [
        'budgets',
        'analysis_rule_configurations',
        'analysis_rule_activations',
      ]),
    );
  });

  test('exports local records and evidence then erases both', () async {
    final root = await Directory.systemTemp.createTemp('butlerly-data-test-');
    addTearDown(() => root.delete(recursive: true));
    final documents = Directory(path.join(root.path, 'documents'))
      ..createSync();
    final evidence = Directory(path.join(root.path, 'evidence'))..createSync();
    final database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    addTearDown(database.close);
    await database.database.insert('merchants', {
      'id': 'merchant-1',
      'name': 'Private merchant',
    });
    await database.database.insert('budgets', {
      'id': 'budget-export',
      'scope': 'overall',
      'scope_id': null,
      'currency': 'USD',
      'amount': '300.00',
      'created_at': '2026-08-09T18:00:00.000Z',
      'updated_at': '2026-08-09T18:00:00.000Z',
    });
    await database.database.insert('analysis_rule_configurations', {
      'rule_id': 'rule-export',
      'configuration': '{}',
      'updated_at': '2026-08-09T18:00:00.000Z',
    });
    await database.database.insert('analysis_rule_activations', {
      'rule_id': 'rule-export',
      'active_rule_version': '1',
      'enabled': 1,
      'updated_at': '2026-08-09T18:00:00.000Z',
    });
    await database.database.insert('provenances', {
      'id': 'provenance-generated-export',
      'source_type': 'manual',
      'captured_at': '2026-08-09T18:00:00.000Z',
    });
    for (final row in const [
      {'id': 'evidence-selected-export', 'local_file_name': 'receipt.bin'},
      {'id': 'evidence-excluded-export', 'local_file_name': 'excluded.bin'},
    ]) {
      await database.database.insert('evidence_items', {
        'id': row['id'],
        'type': 'receipt',
        'original_name': '${row['id']}.pdf',
        'media_type': 'application/pdf',
        'provenance_id': 'provenance-generated-export',
        'created_at': '2026-08-09T18:00:00.000Z',
        'local_file_name': row['local_file_name'],
      });
    }
    for (final id in ['selected-duplicate', 'other-duplicate']) {
      await database.database.insert('transactions', {
        'id': id,
        'occurred_at': '2026-08-09T18:00:00.000Z',
        'amount_coefficient': '25',
        'amount_scale': 0,
        'currency': 'USD',
        'direction': 'expense',
        'source_type': 'manual',
        'status': 'active',
        'created_at': '2026-08-09T18:00:00.000Z',
        'updated_at': '2026-08-09T18:00:00.000Z',
        'transaction_date': '2026-08-09',
      });
      await database.database.insert('transaction_provenances', {
        'transaction_id': id,
        'provenance_id': 'provenance-generated-export',
      });
    }
    const duplicateGroupId = 'duplicate:2026-08-09|25|USD|expense';
    await database.database.insert('duplicate_candidate_groups', {
      'id': duplicateGroupId,
      'transaction_date': '2026-08-09',
      'amount_coefficient': '25',
      'amount_scale': 0,
      'currency': 'USD',
      'direction': 'expense',
      'status': 'consolidated',
      'selected_transaction_id': 'selected-duplicate',
      'created_at': '2026-08-09T18:00:00.000Z',
      'updated_at': '2026-08-09T18:00:00.000Z',
    });
    for (final id in ['selected-duplicate', 'other-duplicate']) {
      await database.database.insert('duplicate_candidate_group_transactions', {
        'group_id': duplicateGroupId,
        'transaction_id': id,
      });
    }
    await database.database.insert('reconciliation_candidates', {
      'id': 'candidate-1',
      'receipt_transaction_id': 'selected-duplicate',
      'payment_transaction_id': 'other-duplicate',
      'score': 0.9,
      'reasons_json': '[]',
      'status': 'proposed',
      'created_at': '2026-08-09T18:00:00.000Z',
      'updated_at': '2026-08-09T18:00:00.000Z',
    });
    await database.database.insert('reconciliation_links', {
      'id': 'link-1',
      'candidate_id': 'candidate-1',
      'receipt_transaction_id': 'selected-duplicate',
      'payment_transaction_id': 'other-duplicate',
      'created_at': '2026-08-09T18:00:00.000Z',
    });
    await database.database.insert('attachment_links', {
      'id': 'attachment-selected-export',
      'transaction_id': 'selected-duplicate',
      'evidence_id': 'evidence-selected-export',
      'created_at': '2026-08-09T18:00:00.000Z',
    });
    await database.database.insert('attachment_links', {
      'id': 'attachment-excluded-export',
      'transaction_id': 'other-duplicate',
      'evidence_id': 'evidence-excluded-export',
      'created_at': '2026-08-09T18:00:00.000Z',
    });
    await database.database.insert('review_issues', {
      'id': 'review-open-export',
      'transaction_id': 'selected-duplicate',
      'reason': 'open generated issue',
      'status': 'open',
      'created_at': '2026-08-09T18:00:00.000Z',
    });
    await database.database.insert('review_issues', {
      'id': 'review-closed-export',
      'transaction_id': 'selected-duplicate',
      'reason': 'closed historical issue',
      'status': 'closed',
      'created_at': '2026-08-09T18:00:00.000Z',
      'closed_at': '2026-08-10T18:00:00.000Z',
    });
    await database.database.insert('suggestions', {
      'id': 'suggestion-pending-export',
      'transaction_id': 'selected-duplicate',
      'target': 'category',
      'proposed_value': 'category.food',
      'method': 'manual',
      'status': 'pending',
      'provenance_id': 'provenance-generated-export',
      'created_at': '2026-08-09T18:00:00.000Z',
    });
    await database.database.insert('suggestions', {
      'id': 'suggestion-decided-export',
      'transaction_id': 'selected-duplicate',
      'target': 'category',
      'proposed_value': 'category.food',
      'method': 'manual',
      'status': 'accepted',
      'provenance_id': 'provenance-generated-export',
      'created_at': '2026-08-09T18:00:00.000Z',
      'decided_at': '2026-08-10T18:00:00.000Z',
    });
    await File(path.join(evidence.path, 'receipt.bin')).writeAsBytes([1, 2, 3]);
    for (final suffix in const [
      '.restore-ambiguous',
      '.restore-previous-ambiguous',
    ]) {
      final abandoned = Directory('${evidence.path}$suffix')
        ..createSync(recursive: true);
      await File(
        path.join(abandoned.path, 'private-receipt.bin'),
      ).writeAsBytes([9, 8, 7]);
    }
    final manager = LocalDataManager(
      database,
      documentsDirectory: documents,
      localEvidenceDirectory: evidence,
      canonicalTransactionIds: (_) async => {'selected-duplicate'},
    );
    for (final suffix in const [
      '.restore-journal.json',
      '.restore-journal.json.tmp',
      '.restore-journal.json.previous',
      '.restore-origin.json',
      '.restore-origin.json.tmp',
      '.restore-origin.json.previous',
    ]) {
      File('${evidence.path}$suffix').writeAsStringSync('{}');
    }
    final abandonedRestoreStage = Directory(
      path.join(root.path, '.butlerly-restore-stage-ambiguous'),
    )..createSync(recursive: true);
    File(
      path.join(abandonedRestoreStage.path, 'private-copy.db'),
    ).writeAsStringSync('private restore copy');
    final privateArtifacts = <File>[
      File(path.join(root.path, '.backup-decrypt-orphan.butlerlybackup')),
      File(path.join(root.path, '.portable-backup-orphan.butlerlybackup')),
      File(path.join(root.path, '.portable-backup-encrypted-orphan')),
      File(path.join(root.path, '.portable-backup-recovery-orphan.json')),
    ];
    for (final file in privateArtifacts) {
      await file.writeAsString('private backup data');
    }

    final exported = await manager.exportAll();
    final exportFile = File(
      path.join(exported.directory.path, 'butlerly-export.json'),
    );
    expect(exportFile.existsSync(), isTrue);
    final json =
        jsonDecode(await exportFile.readAsString()) as Map<String, Object?>;
    final tables = json['tables']! as Map<String, Object?>;
    expect(tables['merchants'], isNotEmpty);
    expect(
      (tables['transactions']! as List).map((row) => (row as Map)['id']),
      contains('selected-duplicate'),
    );
    expect(
      (tables['transactions']! as List).map((row) => (row as Map)['id']),
      isNot(contains('other-duplicate')),
    );
    expect(
      (tables['transaction_provenances']! as List).map(
        (row) => (row as Map)['provenance_id'],
      ),
      contains('provenance-generated-export'),
    );
    expect(
      (tables['duplicate_candidate_groups']! as List).map(
        (row) => (row as Map)['id'],
      ),
      contains(duplicateGroupId),
    );
    expect(
      (tables['evidence_items']! as List).map((row) => (row as Map)['id']),
      ['evidence-selected-export'],
    );
    expect((tables['provenances']! as List).map((row) => (row as Map)['id']), [
      'provenance-generated-export',
    ]);
    expect(
      tables,
      isNot(contains('analysis_rule_results')),
      reason:
          'Export All contains durable source records, not calculated totals.',
    );
    expect(
      (tables['review_issues']! as List).map((row) => (row as Map)['id']),
      ['review-closed-export'],
    );
    expect((tables['suggestions']! as List).map((row) => (row as Map)['id']), [
      'suggestion-decided-export',
    ]);
    expect(tables['reconciliation_candidates'], isEmpty);
    expect(tables['reconciliation_links'], isEmpty);
    expect(
      tables.keys,
      containsAll([
        'financial_statements',
        'statement_rows',
        'reconciliation_candidates',
        'reconciliation_links',
        'category_translations',
        'tag_translations',
        'reference_data',
        'reference_data_translations',
        'budgets',
        'analysis_rule_configurations',
        'analysis_rule_activations',
      ]),
    );
    expect(
      File(
        path.join(exported.directory.path, 'evidence', 'receipt.bin'),
      ).existsSync(),
      isTrue,
    );

    await manager.eraseAll();
    expect(await database.database.query('merchants'), isEmpty);
    for (final table in tables.keys) {
      expect(await database.database.query(table), isEmpty, reason: table);
    }
    expect(evidence.existsSync(), isFalse);
    expect(
      Directory('${evidence.path}.restore-ambiguous').existsSync(),
      isFalse,
    );
    expect(
      Directory('${evidence.path}.restore-previous-ambiguous').existsSync(),
      isFalse,
    );
    expect(abandonedRestoreStage.existsSync(), isFalse);
    for (final file in privateArtifacts) {
      expect(await file.exists(), isFalse, reason: file.path);
    }
    for (final suffix in const [
      '.restore-journal.json',
      '.restore-journal.json.tmp',
      '.restore-journal.json.previous',
      '.restore-origin.json',
      '.restore-origin.json.tmp',
      '.restore-origin.json.previous',
    ]) {
      expect(File('${evidence.path}$suffix').existsSync(), isFalse);
    }
    expect(exported.directory.existsSync(), isFalse);
  });

  test('export rejects symbolic links instead of following them', () async {
    final root = await Directory.systemTemp.createTemp('butlerly-export-link-');
    addTearDown(() => root.delete(recursive: true));
    final documents = Directory(path.join(root.path, 'documents'))
      ..createSync();
    final evidence = Directory(path.join(root.path, 'evidence'))..createSync();
    final database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    addTearDown(database.close);
    final outside = File(path.join(root.path, 'outside.bin'))
      ..writeAsStringSync('private');
    await Link(path.join(evidence.path, 'linked.bin')).create(outside.path);
    final manager = LocalDataManager(
      database,
      documentsDirectory: documents,
      localEvidenceDirectory: evidence,
    );

    await expectLater(manager.exportAll(), throwsA(isA<FormatException>()));
    expect(await outside.readAsString(), 'private');
  });

  test('export rejects missing referenced evidence', () async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-export-missing-',
    );
    addTearDown(() => root.delete(recursive: true));
    final documents = Directory(path.join(root.path, 'documents'))
      ..createSync();
    final evidence = Directory(path.join(root.path, 'evidence'))..createSync();
    final database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    addTearDown(database.close);
    await database.database.insert('provenances', {
      'id': 'provenance-missing-export',
      'source_type': 'manual',
      'captured_at': '2026-10-01T00:00:00.000Z',
    });
    await database.database.insert('evidence_items', {
      'id': 'evidence-missing-export',
      'type': 'receipt',
      'original_name': 'missing.pdf',
      'media_type': 'application/pdf',
      'provenance_id': 'provenance-missing-export',
      'created_at': '2026-10-01T00:00:00.000Z',
      'local_file_name': 'missing.pdf',
    });
    final manager = LocalDataManager(
      database,
      documentsDirectory: documents,
      localEvidenceDirectory: evidence,
    );

    await expectLater(manager.exportAll(), throwsA(isA<StateError>()));
    expect(await documents.list().toList(), isEmpty);
  });

  test('export rejects a symbolic link at the evidence root', () async {
    final root = await Directory.systemTemp.createTemp('butlerly-export-root-');
    addTearDown(() => root.delete(recursive: true));
    final documents = Directory(path.join(root.path, 'documents'))
      ..createSync();
    final evidence = Directory(path.join(root.path, 'evidence'))..createSync();
    final database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    addTearDown(database.close);
    final realEvidence = Directory('${evidence.path}-real');
    await evidence.rename(realEvidence.path);
    await Link(evidence.path).create(realEvidence.path);
    final manager = LocalDataManager(
      database,
      documentsDirectory: documents,
      localEvidenceDirectory: evidence,
    );

    try {
      await expectLater(manager.exportAll(), throwsA(isA<FormatException>()));
    } finally {
      await Link(evidence.path).delete();
      await realEvidence.rename(evidence.path);
    }
  });

  test(
    'export rejects pre-existing staging and destination symlinks',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-export-staging-link-',
      );
      addTearDown(() => root.delete(recursive: true));
      final documents = Directory(path.join(root.path, 'documents'))
        ..createSync();
      final evidence = Directory(path.join(root.path, 'evidence'))
        ..createSync();
      final database = LocalDatabase(
        logger: AppLogger(),
        factory: databaseFactoryFfi,
        databaseDirectory: root.path,
      );
      await database.initialize();
      addTearDown(database.close);
      final now = DateTime.utc(2026, 10, 28, 4);
      final manager = LocalDataManager(
        database,
        documentsDirectory: documents,
        localEvidenceDirectory: evidence,
        clock: () => now,
      );
      final timestamp = now.toIso8601String().replaceAll(':', '-');
      final staging = Directory(
        path.join(documents.path, '.butlerly-export-$timestamp.candidate'),
      );
      final stagingTarget = Directory(path.join(root.path, 'staging-target'))
        ..createSync();
      await Link(staging.path).create(stagingTarget.path);

      await expectLater(manager.exportAll(), throwsA(isA<FormatException>()));
      expect(await stagingTarget.list().toList(), isEmpty);
      expect(
        await FileSystemEntity.type(staging.path, followLinks: false),
        FileSystemEntityType.link,
      );

      await Link(staging.path).delete();
      final destination = Directory(
        path.join(documents.path, 'Butlerly Export $timestamp'),
      );
      final destinationTarget = Directory(
        path.join(root.path, 'destination-target'),
      )..createSync();
      await Link(destination.path).create(destinationTarget.path);

      await expectLater(manager.exportAll(), throwsA(isA<FormatException>()));
      expect(await destinationTarget.list().toList(), isEmpty);
      expect(
        await FileSystemEntity.type(destination.path, followLinks: false),
        FileSystemEntityType.link,
      );
    },
  );
}
