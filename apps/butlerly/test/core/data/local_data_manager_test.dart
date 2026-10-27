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
}
