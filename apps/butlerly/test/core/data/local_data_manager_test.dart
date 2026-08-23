import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
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
    await File(path.join(evidence.path, 'receipt.bin')).writeAsBytes([1, 2, 3]);
    final manager = LocalDataManager(
      database,
      documentsDirectory: documents,
      localEvidenceDirectory: evidence,
    );

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
    expect(exported.directory.existsSync(), isFalse);
  });
}
