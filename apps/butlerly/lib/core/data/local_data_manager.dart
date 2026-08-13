import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/database/local_database.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final class LocalDataExport {
  const LocalDataExport({required this.directory, required this.recordCount});

  final Directory directory;
  final int recordCount;
}

final class LocalDataManager {
  const LocalDataManager(
    this.database, {
    Directory? documentsDirectory,
    Directory? localEvidenceDirectory,
  }) : _documentsDirectory = documentsDirectory,
       _localEvidenceDirectory = localEvidenceDirectory;

  final LocalDatabase database;
  final Directory? _documentsDirectory;
  final Directory? _localEvidenceDirectory;

  static const _exportTables = <String>[
    'payment_sources',
    'merchants',
    'categories',
    'tags',
    'provenances',
    'transactions',
    'transaction_provenances',
    'transaction_tags',
    'review_issues',
    'exchange_rates',
    'normalized_money',
    'evidence_items',
    'extractions',
    'attachment_links',
    'suggestions',
    'user_preferences',
  ];

  static const _eraseOrder = <String>[
    'suggestions',
    'attachment_links',
    'extractions',
    'evidence_items',
    'normalized_money',
    'exchange_rates',
    'review_issues',
    'transaction_tags',
    'transaction_provenances',
    'transactions',
    'payment_sources',
    'merchants',
    'categories',
    'tags',
    'provenances',
    'user_preferences',
  ];

  Future<Directory> evidenceDirectory() async {
    if (_localEvidenceDirectory case final directory?) return directory;
    final support = await getApplicationSupportDirectory();
    return Directory(path.join(support.path, 'evidence'));
  }

  Future<LocalDataExport> exportAll() async {
    final documents =
        _documentsDirectory ?? await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final destination = Directory(
      path.join(documents.path, 'Butlerly Export $timestamp'),
    );
    await destination.create(recursive: true);

    final data = <String, Object?>{
      'format': 'butlerly-finance-export',
      'version': 1,
      'exportedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'tables': <String, Object?>{},
    };
    var recordCount = 0;
    final tables = data['tables']! as Map<String, Object?>;
    for (final table in _exportTables) {
      final rows = await database.database.query(table);
      tables[table] = rows;
      recordCount += rows.length;
    }
    await File(
      path.join(destination.path, 'butlerly-export.json'),
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );

    final evidence = await evidenceDirectory();
    if (await evidence.exists()) {
      final exportedEvidence = Directory(
        path.join(destination.path, 'evidence'),
      );
      await exportedEvidence.create();
      await for (final entity in evidence.list()) {
        if (entity is File) {
          await entity.copy(
            path.join(exportedEvidence.path, path.basename(entity.path)),
          );
        }
      }
    }
    return LocalDataExport(directory: destination, recordCount: recordCount);
  }

  Future<void> eraseAll() async {
    await database.persistenceDatabase.transaction((transaction) async {
      for (final table in _eraseOrder) {
        await transaction.delete(table);
      }
    });
    final evidence = await evidenceDirectory();
    if (await evidence.exists()) await evidence.delete(recursive: true);
  }
}
