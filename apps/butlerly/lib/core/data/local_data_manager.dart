import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
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
    DateTime Function()? clock,
    AnalysisConsistencyGate? consistencyGate,
  }) : _documentsDirectory = documentsDirectory,
       _localEvidenceDirectory = localEvidenceDirectory,
       _clock = clock,
       _consistencyGate = consistencyGate;

  final LocalDatabase database;
  final Directory? _documentsDirectory;
  final Directory? _localEvidenceDirectory;
  final DateTime Function()? _clock;
  final AnalysisConsistencyGate? _consistencyGate;

  static const _exportTables = <String>[
    'payment_sources',
    'payment_settlements',
    'merchants',
    'merchant_aliases',
    'merchant_normalization_patterns',
    'categories',
    'tags',
    'transaction_rules',
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
    'financial_profiles',
    'reconciliation_candidates',
    'reconciliation_links',
    'category_translations',
    'tag_translations',
    'reference_data',
    'reference_data_translations',
    'duplicate_candidate_groups',
    'duplicate_candidate_group_transactions',
    'recurring_pattern_decisions',
    'analysis_rule_configurations',
    'analysis_rule_activations',
    'budgets',
    'entity_tombstones',
  ];

  static const _eraseOrder = <String>[
    'statement_rows',
    'financial_statements',
    'suggestions',
    // Analysis findings and materialized results are derived from the user's
    // financial data and must not survive an erase/restart boundary. Bundled
    // rule definitions and their catalog remain application-owned config.
    'budgets',
    'analysis_rule_configurations',
    'analysis_rule_activations',
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
    'transaction_rules',
    'merchant_normalization_patterns',
    'merchant_aliases',
    'payment_settlements',
    'duplicate_candidate_group_transactions',
    'duplicate_candidate_groups',
    'reconciliation_links',
    'reconciliation_candidates',
    'transactions',
    'payment_sources',
    'merchants',
    'categories',
    'tags',
    'provenances',
    'user_preferences',
    'financial_profiles',
    'recurring_pattern_decisions',
    'reference_data_translations',
    'reference_data',
    'tag_translations',
    'category_translations',
    // Delete triggers above may have created tombstones. Erase-all means the
    // local workspace is intentionally reset, so those tombstones must not
    // survive and suppress records in a later restore.
    'entity_tombstones',
  ];

  static const _generatedExportTombstoneTypes = <String>{
    'review_issues',
    'suggestions',
    'reconciliation_candidates',
    'duplicate_candidate_groups',
    'duplicate_candidate_group_transactions',
  };

  /// Durable user-owned tables included by Export All. Derived analysis
  /// materializations remain intentionally excluded from this contract.
  static List<String> get exportedTableNames =>
      List<String>.unmodifiable(_exportTables);

  /// Tables cleared by Erase All, including derived data and generated
  /// workflow state. The durable subset must remain covered by
  /// [exportedTableNames].
  static List<String> get erasedTableNames =>
      List<String>.unmodifiable(_eraseOrder);

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
    final directory = Directory(
      path.join(databaseDirectory, '.butlerly-recovery'),
    );
    await rejectSymlinkedPath(directory.path);
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> safetyBackupDirectory() async {
    final recovery = await recoveryDirectory();
    final directory = Directory(path.join(recovery.path, 'safety-backups'));
    await rejectSymlinkedPath(directory.path);
    await directory.create(recursive: true);
    return directory;
  }

  /// Keeps the newest validated safety snapshots and removes older recovery
  /// copies after a restore has completed successfully.
  Future<void> pruneSafetyBackups({int keep = 2, String? preservePath}) async {
    if (keep < 0) throw ArgumentError.value(keep, 'keep');
    final directory = await safetyBackupDirectory();
    if (!await directory.exists()) return;
    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.butlerlybackup')) {
        files.add(entity);
      }
    }
    files.sort((left, right) {
      final leftModified = left.lastModifiedSync();
      final rightModified = right.lastModifiedSync();
      return rightModified.compareTo(leftModified);
    });

    var retained = 0;
    for (final file in files) {
      if (preservePath != null && path.equals(file.path, preservePath)) {
        continue;
      }
      if (retained < keep) {
        retained++;
        continue;
      }
      await file.delete();
    }

    // Interrupted internal package creation can leave only incomplete siblings;
    // they are never valid safety snapshots and should not accumulate forever.
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      if (name.contains('.candidate-') || name.contains('.tmp-')) {
        try {
          await entity.delete();
        } on Exception {
          // Best-effort retention cleanup must not affect a completed restore.
        }
      }
    }
  }

  Future<LocalDataExport> exportAll() => EvidenceMutationLock.runExclusive(
    () async {
      final documents = await documentsDirectory();
      await rejectEvidenceRoot(documents, message: 'Unsafe documents root.');
      final timestamp = (_clock?.call() ?? DateTime.now())
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-');
      final destination = Directory(
        path.join(documents.path, 'Butlerly Export $timestamp'),
      );
      final staging = Directory(
        path.join(documents.path, '.butlerly-export-$timestamp.candidate'),
      );
      await _ensureFreshExportPath(destination);
      await _ensureFreshExportPath(staging);
      await staging.create(recursive: true);

      final data = <String, Object?>{
        'format': 'butlerly-finance-export',
        'version': 1,
        'exportedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'tables': <String, Object?>{},
      };
      var recordCount = 0;
      final tables = data['tables']! as Map<String, Object?>;
      final evidence = await evidenceDirectory();
      await rejectEvidenceRoot(evidence);
      try {
        // Keep the database snapshot and evidence tree under the same mutation
        // boundary. The read transaction remains open while evidence is copied,
        // so the exported JSON and files describe one logical local state.
        await database.persistenceDatabase.transaction((snapshot) async {
          Future<List<Map<String, Object?>>> rowsFor(String table) async {
            switch (table) {
              case 'review_issues':
                return snapshot.query(table, where: 'closed_at IS NOT NULL');
              case 'suggestions':
                return snapshot.query(table, where: 'decided_at IS NOT NULL');
              case 'transactions':
                return snapshot.query(table);
              case 'reconciliation_candidates':
                return snapshot.query(table, where: "status != 'proposed'");
              case 'reconciliation_links':
                final candidates = await rowsFor('reconciliation_candidates');
                final ids = candidates
                    .map((row) => row['id'])
                    .whereType<String>()
                    .toSet();
                final rows = await snapshot.query(table);
                return rows
                    .where((row) => ids.contains(row['candidate_id']))
                    .toList(growable: false);
              case 'evidence_items':
                return snapshot.query(table);
              case 'extractions':
                return snapshot.query(table);
              case 'provenances':
                return snapshot.query(table);
              case 'duplicate_candidate_groups':
                // Export All preserves review state exactly, including an
                // ordinary unresolved duplicate group. Backup-specific
                // durability filtering must not remove source records from a
                // user-requested data export.
                return snapshot.query(table);
              case 'duplicate_candidate_group_transactions':
                final groups = await rowsFor('duplicate_candidate_groups');
                final ids = groups
                    .map((row) => row['id'])
                    .whereType<String>()
                    .toSet();
                final rows = await snapshot.query(table);
                return rows
                    .where((row) => ids.contains(row['group_id']))
                    .toList(growable: false);
              case 'entity_tombstones':
                final rows = await snapshot.query(table);
                return rows
                    .where(
                      (row) => !_generatedExportTombstoneTypes.contains(
                        row['entity_type'],
                      ),
                    )
                    .toList(growable: false);
              default:
                return snapshot.query(table);
            }
          }

          for (final table in _exportTables) {
            final rows = await rowsFor(table);
            tables[table] = rows;
            recordCount += rows.length;
          }
          final evidenceRows = (tables['evidence_items']! as List)
              .cast<Map<String, Object?>>();
          for (final row in evidenceRows) {
            final localName = row['local_file_name'] as String?;
            if (localName == null || localName.trim().isEmpty) continue;
            final normalized = await validateEvidenceReferencePath(
              evidence,
              localName,
              message: 'Unsafe local evidence path.',
            );
            if (!await File(path.join(evidence.path, normalized)).exists()) {
              throw StateError('Referenced evidence file is missing.');
            }
          }
          await File(
            path.join(staging.path, 'butlerly-export.json'),
          ).writeAsString(
            const JsonEncoder.withIndent('  ').convert(data),
            flush: true,
          );

          if (await evidence.exists()) {
            final exportedEvidence = Directory(
              path.join(staging.path, 'evidence'),
            );
            await exportedEvidence.create();
            await for (final entity in evidence.list(
              recursive: true,
              followLinks: false,
            )) {
              await rejectEvidenceLink(entity);
              if (entity is File) {
                final relative = await validateEvidencePath(
                  evidence,
                  path.relative(entity.path, from: evidence.path),
                );
                final target = File(path.join(exportedEvidence.path, relative));
                await target.parent.create(recursive: true);
                await entity.copy(target.path);
              }
            }
          }
        });
        await staging.rename(destination.path);
        return LocalDataExport(
          directory: destination,
          recordCount: recordCount,
        );
      } catch (_) {
        if (await staging.exists()) {
          await staging.delete(recursive: true);
        }
        rethrow;
      }
    },
  );

  Future<void> _ensureFreshExportPath(Directory candidate) async {
    await rejectSymlinkedPath(candidate.path, message: 'Unsafe export path.');
    if (await FileSystemEntity.type(candidate.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FormatException('Export path already exists.');
    }
  }

  Future<void> eraseAll({
    bool preserveRecoveryMarker = false,
  }) => _runConsistently(
    () => EvidenceMutationLock.runExclusive(() async {
      // Validate every recursive deletion target before touching SQLite. If a
      // caller or a corrupted recovery artifact has introduced a symlink, fail
      // closed while all financial data is still intact.
      final evidence = await evidenceDirectory();
      final pendingEvidence = await pendingEvidenceDirectory();
      final evidenceParent = evidence.parent;
      final databaseDirectory = Directory(
        path.dirname(database.persistenceDatabase.path),
      );
      final recovery = Directory(
        path.join(databaseDirectory.path, '.butlerly-recovery'),
      );
      final documents = await documentsDirectory();
      await rejectEvidenceTree(evidence, message: 'Unsafe live evidence tree.');
      await rejectEvidenceTree(
        pendingEvidence,
        message: 'Unsafe pending evidence tree.',
      );
      await rejectEvidenceTree(recovery, message: 'Unsafe recovery tree.');
      await rejectEvidenceRoot(
        databaseDirectory,
        message: 'Unsafe private data root.',
      );
      if (await evidenceParent.exists()) {
        final restorePrefix = '${path.basename(evidence.path)}.restore-';
        await for (final entity in evidenceParent.list(followLinks: false)) {
          final name = path.basename(entity.path);
          if (!name.startsWith(restorePrefix)) continue;
          if (entity is Link) {
            throw const FormatException('Unsafe restore evidence tree.');
          }
          if (entity is Directory) {
            await rejectEvidenceTree(
              entity,
              message: 'Unsafe restore evidence tree.',
            );
          }
        }
      }
      if (await databaseDirectory.exists()) {
        await for (final entity in databaseDirectory.list(followLinks: false)) {
          if (entity is Link) {
            final name = path.basename(entity.path);
            if (name.startsWith('.butlerly-restore-stage-') ||
                name.startsWith('.backup-decrypt-') ||
                name.startsWith('.portable-backup-')) {
              throw const FormatException('Unsafe private recovery artifact.');
            }
          } else if (entity is Directory &&
              path
                  .basename(entity.path)
                  .startsWith('.butlerly-restore-stage-')) {
            await rejectEvidenceTree(
              entity,
              message: 'Unsafe restore staging tree.',
            );
          }
        }
      }
      await rejectEvidenceRoot(documents, message: 'Unsafe documents root.');
      if (await documents.exists()) {
        await for (final entity in documents.list(followLinks: false)) {
          final name = path.basename(entity.path);
          final removable =
              name.startsWith('Butlerly Export ') ||
              name == 'Butlerly Safety Backups';
          if (!removable) continue;
          if (entity is Link) {
            throw const FormatException('Unsafe export artifact.');
          }
          if (entity is Directory) {
            await rejectEvidenceTree(
              entity,
              message: 'Unsafe export artifact.',
            );
          }
        }
      }
      final markerPaths = <String>[
        '${evidence.path}.restore-recovery-required.json',
        '${evidence.path}.restore-recovery-required.json.tmp',
        '${evidence.path}.restore-recovery-required.json.previous',
        '${evidence.path}.restore-journal.json',
        '${evidence.path}.restore-journal.json.tmp',
        '${evidence.path}.restore-journal.json.previous',
        '${evidence.path}.restore-origin.json',
        '${evidence.path}.restore-origin.json.tmp',
        '${evidence.path}.restore-origin.json.previous',
      ];
      for (final markerPath in markerPaths) {
        if (await FileSystemEntity.type(markerPath, followLinks: false) ==
            FileSystemEntityType.link) {
          throw const FormatException('Unsafe recovery marker.');
        }
      }

      // Privacy reset and restore share one evidence mutation boundary.
      await database.persistenceDatabase.transaction((transaction) async {
        for (final table in _eraseOrder) {
          await transaction.delete(table);
        }
      });
      if (await evidence.exists()) await evidence.delete(recursive: true);
      if (await evidenceParent.exists()) {
        final restorePrefix = '${path.basename(evidence.path)}.restore-';
        await for (final entity in evidenceParent.list(followLinks: false)) {
          if (entity is Directory &&
              path.basename(entity.path).startsWith(restorePrefix)) {
            await entity.delete(recursive: true);
          }
        }
      }
      if (await pendingEvidence.exists()) {
        await pendingEvidence.delete(recursive: true);
      }

      // Restore staging workspaces contain private SQLite and evidence copies.
      // They are normally removed when a restore finishes, but an interrupted
      // recovery reset must not leave them behind after an explicit erase-all.
      if (await databaseDirectory.exists()) {
        await for (final entity in databaseDirectory.list(followLinks: false)) {
          if (entity is Directory &&
              path
                  .basename(entity.path)
                  .startsWith('.butlerly-restore-stage-')) {
            await entity.delete(recursive: true);
          }
        }

        // Erase All is an explicit privacy boundary. Remove private backup,
        // decryption, and publication-recovery artifacts too, including any
        // artifacts protected from ordinary startup cleanup for recovery.
        await for (final entity in databaseDirectory.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = path.basename(entity.path);
          if (name.startsWith('.backup-decrypt-') ||
              name.startsWith('.portable-backup-')) {
            await entity.delete();
          }
        }
      }

      // Recovery snapshots contain user financial state and are part of an
      // erase-all boundary. A recovery reset may intentionally keep the marker
      // until system-data reseeding/runtime refresh also succeeds.
      if (await recovery.exists()) await recovery.delete(recursive: true);
      if (!preserveRecoveryMarker) {
        final recoveryMarker = File(
          '${evidence.path}.restore-recovery-required.json',
        );
        for (final file in <File>[
          recoveryMarker,
          File('${recoveryMarker.path}.tmp'),
          File('${recoveryMarker.path}.previous'),
        ]) {
          if (await file.exists()) await file.delete();
        }
      }
      for (final file in <File>[
        File('${evidence.path}.restore-journal.json'),
        File('${evidence.path}.restore-journal.json.tmp'),
        File('${evidence.path}.restore-journal.json.previous'),
        File('${evidence.path}.restore-origin.json'),
        File('${evidence.path}.restore-origin.json.tmp'),
        File('${evidence.path}.restore-origin.json.previous'),
      ]) {
        if (await file.exists()) await file.delete();
      }

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
    }),
  );

  Future<T> _runConsistently<T>(Future<T> Function() operation) {
    final gate = _consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}
