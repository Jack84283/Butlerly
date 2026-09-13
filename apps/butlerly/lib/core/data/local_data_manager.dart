import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
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
    'financial_statements',
    'statement_rows',
    'extractions',
    'attachment_links',
    'suggestions',
    'user_preferences',
    'reconciliation_candidates',
    'reconciliation_links',
    'category_translations',
    'tag_translations',
    'reference_data',
    'reference_data_translations',
    'duplicate_candidate_groups',
    'duplicate_candidate_group_transactions',
    'entity_tombstones',
  ];

  static const _eraseOrder = <String>[
    'statement_rows',
    'financial_statements',
    'suggestions',
    // Analysis findings and materialized results are derived from the user's
    // financial data and must not survive an erase/restart boundary. Bundled
    // rule definitions and their catalog remain application-owned config.
    'analysis_findings',
    'analysis_rule_results',
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
    'reconciliation_links',
    'reconciliation_candidates',
    'duplicate_candidate_group_transactions',
    'duplicate_candidate_groups',
    'reference_data_translations',
    'reference_data',
    'tag_translations',
    'category_translations',
    // Delete triggers above may have created tombstones. Erase-all means the
    // local workspace is intentionally reset, so those tombstones must not
    // survive and suppress records in a later restore.
    'entity_tombstones',
  ];

  Future<Directory> evidenceDirectory() async {
    if (_localEvidenceDirectory case final directory?) return directory;
    final support = await getApplicationSupportDirectory();
    return Directory(path.join(support.path, 'evidence'));
  }

  /// Temporary home for captures that have not yet been published to SQLite.
  ///
  /// This must remain outside [evidenceDirectory] because restore is allowed to
  /// replace the live evidence root while a receipt is still in OCR/review.
  Future<Directory> pendingEvidenceDirectory() async =>
      Directory('${(await evidenceDirectory()).path}.pending');

  Future<Directory> documentsDirectory() async =>
      _documentsDirectory ?? await getApplicationDocumentsDirectory();

  /// Application-private recovery state. Unlike user exports, automatic safety
  /// snapshots must never be written to the user-visible Documents location.
  Future<Directory> recoveryDirectory() async {
    final databaseDirectory = path.dirname(database.persistenceDatabase.path);
    final directory = Directory(path.join(databaseDirectory, '.butlerly-recovery'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> safetyBackupDirectory() async {
    final recovery = await recoveryDirectory();
    final directory = Directory(path.join(recovery.path, 'safety-backups'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<LocalDataExport> exportAll() async {
    final documents = await documentsDirectory();
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
      await for (final entity in evidence.list(recursive: true)) {
        if (entity is File) {
          final relative = path.relative(entity.path, from: evidence.path);
          final destination = File(path.join(exportedEvidence.path, relative));
          await destination.parent.create(recursive: true);
          await entity.copy(destination.path);
        }
      }
    }
    return LocalDataExport(directory: destination, recordCount: recordCount);
  }

  Future<void> eraseAll() => EvidenceMutationLock.runExclusive(() async {
    // Privacy reset and restore share one evidence mutation boundary. Whichever
    // operation acquires the lock first completes first; if erase follows an
    // active restore, the final durable state is still erased and restore cannot
    // repopulate the workspace after the reset returns.
    await database.persistenceDatabase.transaction((transaction) async {
      for (final table in _eraseOrder) {
        await transaction.delete(table);
      }
    });
    final evidence = await evidenceDirectory();
    if (await evidence.exists()) await evidence.delete(recursive: true);
    final pendingEvidence = await pendingEvidenceDirectory();
    if (await pendingEvidence.exists()) {
      await pendingEvidence.delete(recursive: true);
    }

    // Recovery snapshots and fail-closed marker artifacts contain or protect
    // user financial state and are part of an erase-all boundary.
    final recovery = Directory(
      path.join(
        path.dirname(database.persistenceDatabase.path),
        '.butlerly-recovery',
      ),
    );
    if (await recovery.exists()) await recovery.delete(recursive: true);
    final recoveryMarker = File('${evidence.path}.restore-recovery-required.json');
    for (final file in <File>[
      recoveryMarker,
      File('${recoveryMarker.path}.tmp'),
      File('${recoveryMarker.path}.previous'),
    ]) {
      if (await file.exists()) await file.delete();
    }

    final documents = await documentsDirectory();
    if (await documents.exists()) {
      await for (final entity in documents.list()) {
        if (entity is Directory &&
            (path.basename(entity.path).startsWith('Butlerly Export ') ||
                // Remove legacy safety-backup directories created by builds
                // before recovery data moved to application-private storage.
                path.basename(entity.path) == 'Butlerly Safety Backups')) {
          await entity.delete(recursive: true);
        }
      }
    }
  });
}
