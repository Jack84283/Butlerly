import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/backup_container_format.dart';
import 'package:butlerly/core/data/duplicate_group_backup_policy.dart';
import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/staged_evidence_restore_reconciliation.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart'
    hide Transaction;
import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';

export 'package:butlerly_finance_application/butlerly_finance_application.dart'
    show
        LocalRestoreMode,
        BackupChangeSummary,
        BackupInspection,
        LocalRestoreResult;

final class _TableSpec {
  const _TableSpec(
    this.name,
    this.keys, {
    this.updatedAt,
    this.createdAt,
    this.systemOwned = false,
    this.mergeUnion = false,
    this.preserveLocalOnMergeConflict = false,
  });

  final String name;
  final List<String> keys;
  final String? updatedAt;
  final String? createdAt;
  final bool systemOwned;
  final bool mergeUnion;
  final bool preserveLocalOnMergeConflict;
}

final class _EvidenceDescriptor {
  const _EvidenceDescriptor({
    required this.relativePath,
    required this.length,
    required this.sha256,
    required this.offset,
  });

  final String relativePath;
  final int length;
  final String sha256;
  final int offset;
}

final class _BackupPackage {
  const _BackupPackage({
    required this.file,
    required this.manifest,
    required this.tables,
    required this.evidence,
  });

  final File file;
  final Map<String, Object?> manifest;
  final Map<String, Object?> tables;
  final List<_EvidenceDescriptor> evidence;
}

final class _PreparedEvidence {
  const _PreparedEvidence({
    required this.directory,
    required this.addedCount,
    required this.pathRemaps,
    required this.expectedHashes,
  });

  final Directory directory;
  final int addedCount;
  final Map<String, String> pathRemaps;
  final Map<String, String> expectedHashes;
}

final class LocalBackupManager {
  const LocalBackupManager(this.database, this.localDataManager);

  static const _builtInTagIds = <String>{
    'tag.business',
    'tag.personal',
    'tag.reimbursable',
    'tag.tax_related',
    'tag.travel',
    'tag.recurring',
    'tag.subscription',
  };

  final LocalDatabase database;
  final LocalDataManager localDataManager;

  static const format = BackupContainerFormat.name;
  static const formatVersion = BackupContainerFormat.version;
  static const schemaVersion = BackupContainerFormat.schemaVersion;
  static final _magic = BackupContainerFormat.magic;

  static const _tables = <_TableSpec>[
    _TableSpec(
      'payment_sources',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'categories',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
      systemOwned: true,
    ),
    _TableSpec('category_translations', [
      'category_id',
      'locale',
    ], preserveLocalOnMergeConflict: true),
    _TableSpec(
      'merchants',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
      systemOwned: true,
    ),
    _TableSpec(
      'merchant_aliases',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'merchant_normalization_patterns',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'tags',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
      systemOwned: true,
    ),
    _TableSpec('tag_translations', [
      'tag_id',
      'locale',
    ], preserveLocalOnMergeConflict: true),
    _TableSpec('provenances', ['id'], createdAt: 'captured_at'),
    _TableSpec('exchange_rates', ['id'], createdAt: 'effective_at'),
    _TableSpec(
      'transactions',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'payment_settlements',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec('normalized_money', [
      'transaction_id',
      'exchange_rate_id',
    ], updatedAt: 'updated_at'),
    _TableSpec('transaction_provenances', [
      'transaction_id',
      'provenance_id',
    ], mergeUnion: true),
    _TableSpec('transaction_tags', [
      'transaction_id',
      'tag_id',
    ], createdAt: 'created_at'),
    _TableSpec(
      'transaction_rules',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec('evidence_items', ['id'], createdAt: 'created_at'),
    _TableSpec(
      'financial_statements',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'statement_rows',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec('extractions', ['id'], createdAt: 'created_at'),
    _TableSpec('attachment_links', ['id'], createdAt: 'created_at'),
    _TableSpec(
      'suggestions',
      ['id'],
      updatedAt: 'decided_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'review_issues',
      ['id'],
      updatedAt: 'closed_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'reconciliation_candidates',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec('reconciliation_links', ['id'], createdAt: 'created_at'),
    _TableSpec(
      'duplicate_candidate_groups',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec('duplicate_candidate_group_transactions', [
      'group_id',
      'transaction_id',
    ]),
    _TableSpec(
      'recurring_pattern_decisions',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec('analysis_rule_activations', [
      'rule_id',
    ], updatedAt: 'updated_at'),
    _TableSpec('analysis_rule_configurations', [
      'rule_id',
    ], updatedAt: 'updated_at'),
    _TableSpec('reference_data', ['id'], preserveLocalOnMergeConflict: true),
    _TableSpec('reference_data_translations', [
      'reference_data_id',
      'locale',
    ], preserveLocalOnMergeConflict: true),
    _TableSpec('user_preferences', ['id'], updatedAt: 'updated_at'),
    _TableSpec(
      'financial_profiles',
      ['profile_id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'budgets',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
  ];

  /// Returns the table keys emitted by the current snapshot writer, plus the
  /// tombstone table handled outside the merge specs. Legacy backup schemas
  /// intentionally omit a small number of keys; callers use
  /// [requiredTablesForSchema] to preserve those compatibility rules.
  static Set<String> get backupTableNames => {
    for (final table in _tables) table.name,
    'entity_tombstones',
  };

  static Set<String> requiredTablesForSchema(int sourceSchema) {
    final required = backupTableNames;
    if (sourceSchema <= 13) {
      // Schema 13 was emitted both before and after budgets were introduced.
      // Treat it as a compatibility family: budgets may be absent from a
      // legitimate historical schema-13 package. Schema 14 is the first
      // schema that requires budgets.
      required.removeAll(const {
        'category_translations',
        'tag_translations',
        'reference_data',
        'reference_data_translations',
        'budgets',
      });
    }
    if (sourceSchema <= 14) {
      required.remove('financial_profiles');
    }
    if (sourceSchema <= 11) {
      required.remove('recurring_pattern_decisions');
    }
    if (sourceSchema <= 8) {
      required.remove('payment_settlements');
    }
    return required;
  }

  static final _specByName = <String, _TableSpec>{
    for (final spec in _tables) spec.name: spec,
  };

  static final _enumColumnsByTable = <String, Map<String, Set<String>>>{
    'payment_sources': {
      'type': _enumNames(PaymentSourceType.values),
      'status': _enumNames(PaymentSourceStatus.values),
    },
    'categories': {
      'origin': _enumNames(CategoryOrigin.values),
      'status': _enumNames(CategoryStatus.values),
    },
    'merchants': {'status': _enumNames(MerchantStatus.values)},
    'merchant_aliases': {'status': _enumNames(MerchantMatchingStatus.values)},
    'merchant_normalization_patterns': {
      'status': _enumNames(MerchantMatchingStatus.values),
    },
    'tags': {'status': _enumNames(TagStatus.values)},
    'provenances': {
      // `manual` was emitted by early local-first builds before provenance
      // sources were split into the current enum values.
      'source_type': {..._enumNames(ProvenanceSourceType.values), 'manual'},
    },
    'transactions': {
      'direction': _enumNames(TransactionDirection.values),
      'source_type': _enumNames(TransactionSourceType.values),
      'status': _enumNames(TransactionStatus.values),
    },
    'payment_settlements': {
      'status': _enumNames(PaymentSettlementStatus.values),
    },
    'normalized_money': {
      // `manual` was the historical spelling for user-entered normalization.
      'normalization_source': {
        ..._enumNames(NormalizationSource.values),
        'manual',
      },
    },
    'evidence_items': {
      // These are persisted reference-data values from the pre-enum schema.
      'type': {..._enumNames(EvidenceType.values), 'receipt', 'statement'},
    },
    'financial_statements': {
      'status': {..._enumNames(StatementStatus.values), 'processed'},
    },
    'statement_rows': {
      'row_kind': {..._enumNames(StatementRowKind.values), 'transaction'},
      'status': _enumNames(StatementRowStatus.values),
      'status_before_skip': _enumNames(StatementRowStatus.values),
    },
    'suggestions': {
      'target': _enumNames(SuggestionTarget.values),
      // `local` is the historical spelling for the current localAi method.
      'method': {..._enumNames(SuggestionMethod.values), 'local'},
      'status': _enumNames(SuggestionStatus.values),
    },
    'review_issues': {
      'reason': _enumNames(ReviewIssueReason.values),
      'status': _enumNames(ReviewIssueStatus.values),
    },
    'reconciliation_candidates': {
      'status': _enumNames(ReconciliationCandidateStatus.values),
    },
    'duplicate_candidate_groups': {
      'status': _enumNames(DuplicateCandidateGroupStatus.values),
    },
    'recurring_pattern_decisions': {
      'status': _enumNames(RecurringPatternDecisionStatus.values),
      'cadence': _enumNames(RecurringPatternDecisionCadence.values),
    },
    'budgets': {
      'scope': {'overall', 'category', 'subcategory', 'merchant'},
    },
    'financial_profiles': {
      'household_size': _enumNames(HouseholdSize.values),
      'dependents_count': _enumNames(DependentsCount.values),
      'housing_situation': _enumNames(HousingSituation.values),
      'expense_predictability': _enumNames(ExpensePredictability.values),
      'primary_financial_goal': _enumNames(PrimaryFinancialGoal.values),
      'goal_timeframe': _enumNames(GoalTimeframe.values),
      'budgeting_preference': _enumNames(BudgetingPreference.values),
      'survey_status': {'notStarted', 'inProgress', 'completed'},
    },
    'reference_data': {
      'origin': _enumNames(ReferenceDataOrigin.values),
      'status': _enumNames(ReferenceDataStatus.values),
    },
  };

  static Set<String> _enumNames<T extends Enum>(List<T> values) =>
      values.map((value) => value.name).toSet();

  static const _derivedTables = <String>[
    'analysis_findings',
    'analysis_rule_results',
  ];

  Future<BackupInspection> inspect(File file) async {
    final package = await _readPackage(file);
    final createdAt = DateTime.parse(
      package.manifest['createdAtUtc']! as String,
    ).toUtc();
    return BackupInspection(
      createdAtUtc: createdAt,
      recordCount: package.manifest['recordCount']! as int,
      evidenceCount: package.manifest['evidenceCount']! as int,
      changes: await _newerLocalSummary(createdAt, package.tables),
    );
  }

  Future<LocalRestoreResult> restore(
    File file, {
    required LocalRestoreMode mode,
  }) async {
    // Package parsing, evidence integrity verification, and construction of the
    // final staging tree all finish before the live database is mutated.
    final package = await _readPackage(file);
    final backupTime = DateTime.parse(
      package.manifest['createdAtUtc']! as String,
    ).toUtc();
    final tablePayload = <String, Object?>{...package.tables};
    _migratePaymentSettlementBackupPayload(
      tablePayload,
      package.manifest['schemaVersion']! as int,
    );
    final durableUnresolvedDuplicateGroupIds =
        DuplicateGroupBackupPolicy.durableUnresolvedGroupIds(
          groups: _tableRows(tablePayload, 'duplicate_candidate_groups'),
          memberships: _tableRows(
            tablePayload,
            'duplicate_candidate_group_transactions',
          ),
          transactions: _tableRows(tablePayload, 'transactions'),
        );
    final root = await localDataManager.evidenceDirectory();
    final deleting = Directory('${root.path}.deleting');
    final operationId = 'restore-${DateTime.now().microsecondsSinceEpoch}';
    final previous = Directory('${root.path}.restore-previous-$operationId');
    final previousDeleting = Directory(
      '${root.path}.restore-deleting-$operationId',
    );
    final journal = File('${root.path}.restore-journal.json');
    _PreparedEvidence? prepared;
    try {
      prepared = await _prepareEvidence(package, mode: mode);
      _applyEvidenceRemaps(tablePayload, prepared.pathRemaps);
      await _validateEvidenceReferences(
        tablePayload,
        prepared.directory,
        expectedHashes: prepared.expectedHashes,
      );
      await _writeJournal(
        journal,
        operationId,
        previous.path,
        prepared.directory.path,
        'prepared',
        previousDeleting: previousDeleting.path,
        mode: mode,
      );
    } catch (_) {
      // No live state has been activated yet. A validation or journal
      // initialization failure must not leave a private evidence copy behind.
      final staging = prepared?.directory;
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }
    final preparedEvidence = prepared;

    var restoredRows = 0;
    var keptNewer = 0;
    var evidenceActivated = false;
    var deletingActivated = false;
    var stagedDeletionUnresolved = false;
    var databaseCommitted = false;
    try {
      await rejectEvidenceRoot(
        deleting,
        message: 'Unsafe staged deletion root.',
      );
      if (await deleting.exists()) {
        await deleting.rename(previousDeleting.path);
        deletingActivated = true;
      }
      if (await root.exists()) await root.rename(previous.path);
      await preparedEvidence.directory.rename(root.path);
      evidenceActivated = true;
      await _writeJournal(
        journal,
        operationId,
        previous.path,
        preparedEvidence.directory.path,
        'evidenceActivated',
        previousDeleting: previousDeleting.path,
        mode: mode,
      );
      await database.database.transaction((tx) async {
        final durableGroupIdsToPreserve = mode == LocalRestoreMode.merge
            ? {
                ...durableUnresolvedDuplicateGroupIds,
                ...await _durableUnresolvedDuplicateGroupIdsFromDatabase(tx),
              }
            : durableUnresolvedDuplicateGroupIds;
        await _writeJournal(
          journal,
          operationId,
          previous.path,
          preparedEvidence.directory.path,
          'dbWriting',
          previousDeleting: previousDeleting.path,
          mode: mode,
        );

        Set<String> protectedTransactions = const <String>{};
        if (mode == LocalRestoreMode.replace) {
          await _clearPortableState(tx);
        } else {
          // Generated workflow state is not authoritative. Purge it first, but
          // keep the purge in this transaction so any later failure rolls it
          // back together with the restore.
          await _purgeGeneratedWorkflowState(
            tx,
            preserveDuplicateGroupIds: durableGroupIdsToPreserve,
          );
          protectedTransactions = await _protectedTransactionIds(
            tx,
            tablePayload,
            backupTime,
          );

          // restore_context is strictly transaction-scoped. No user write can
          // observe trigger suppression outside this SQLite writer transaction.
          await tx.insert('restore_context', {
            'id': 1,
            'backup_time': backupTime.toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        try {
          if (mode == LocalRestoreMode.merge) {
            keptNewer += await _applyBackupTombstones(
              tx,
              tablePayload,
              backupTime,
            );
          }
          for (final spec in _tables) {
            var payload =
                (tablePayload[spec.name] as List? ?? const <Object?>[])
                    .cast<Map>()
                    .map((row) => row.cast<String, Object?>());
            if (spec.name == 'categories') {
              payload = _orderCategories(payload.toList(growable: false));
            }
            for (final row in payload) {
              if (await _isSystemOwned(tx, spec, row)) continue;
              if (mode == LocalRestoreMode.merge) {
                if (_referencesProtectedTransaction(
                  spec,
                  row,
                  protectedTransactions,
                )) {
                  keptNewer++;
                  continue;
                }
                if (await _hasNewerLocalTombstone(tx, spec, row, backupTime)) {
                  keptNewer++;
                  continue;
                }
                final local = await _findRow(tx, spec, row);
                if (local != null &&
                    !_rowsEqual(local, row) &&
                    (spec.preserveLocalOnMergeConflict ||
                        _rowChangedAfter(local, spec, backupTime))) {
                  keptNewer++;
                  continue;
                }
              }
              await _upsertRow(tx, spec, row);
              await _clearTombstoneForRestoredRow(tx, spec, row);
              restoredRows++;
            }
          }
          if (mode == LocalRestoreMode.replace) {
            final tombstones =
                (tablePayload['entity_tombstones'] as List? ??
                        const <Object?>[])
                    .cast<Map>();
            for (final raw in tombstones) {
              final row = raw.cast<String, Object?>();
              final entityType = row['entity_type'] as String?;
              final entityId = row['entity_id'];
              final spec = entityType == null ? null : _specByName[entityType];
              if (spec == null || entityId == null) {
                throw const FormatException('Invalid backup tombstone.');
              }
              final values = _keyValuesFromTombstone(spec, '$entityId');
              if (values == null) {
                throw const FormatException(
                  'Invalid backup tombstone identity.',
                );
              }
              final localRows = await _queryByKeys(tx, spec, values);
              if (localRows.isNotEmpty &&
                  await _isSystemOwned(tx, spec, localRows.single)) {
                continue;
              }
              await tx.insert(
                'entity_tombstones',
                row,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        } finally {
          if (mode == LocalRestoreMode.merge) {
            await tx.delete('restore_context', where: 'id = 1');
          }
        }

        // Older format-v2 packages may contain generated workflow rows. Purge
        // again after restore_context is gone so trigger preservation cannot
        // keep generated rows, while durable decisions remain intact.
        await _purgeGeneratedWorkflowState(
          tx,
          preserveDuplicateGroupIds: durableGroupIdsToPreserve,
        );

        for (final table in _derivedTables) {
          await tx.delete(table);
        }
        await tx.insert('restore_commits', {
          'operation_id': operationId,
          'committed_at': DateTime.now().toUtc().toIso8601String(),
        });
      });
      databaseCommitted = true;
      if (await previousDeleting.exists()) {
        stagedDeletionUnresolved = await reconcileStagedEvidenceAfterRestore(
          database.database,
          root,
          previousDeleting,
        );
        if (stagedDeletionUnresolved && !await deleting.exists()) {
          await previousDeleting.rename(deleting.path);
        }
      }

      // The durable DB marker, not this advisory journal phase, is the source
      // of truth after commit. If this write fails, keep the new evidence tree
      // and leave recovery artifacts for startup cleanup rather than entering
      // the pre-commit rollback path.
      try {
        await _writeJournal(
          journal,
          operationId,
          previous.path,
          preparedEvidence.directory.path,
          'dbCommitted',
          previousDeleting: previousDeleting.path,
          mode: mode,
        );
      } on Exception {
        return LocalRestoreResult(
          mode: mode,
          restoredRows: restoredRows,
          keptNewerLocalRows: keptNewer,
          restoredEvidence: preparedEvidence.addedCount,
        );
      }
    } catch (_) {
      if (!databaseCommitted) {
        if (evidenceActivated) {
          if (await root.exists()) await root.delete(recursive: true);
          if (await previous.exists()) await previous.rename(root.path);
        } else if (await preparedEvidence.directory.exists()) {
          await preparedEvidence.directory.delete(recursive: true);
        }
        if (deletingActivated && await previousDeleting.exists()) {
          if (!await deleting.exists()) {
            await previousDeleting.rename(deleting.path);
          }
        }
        if (await journal.exists() &&
            (!await previousDeleting.exists() || !deletingActivated)) {
          await journal.delete();
        }
      }
      rethrow;
    }

    // Cleanup is best effort after the durable commit. Any interruption leaves
    // enough marker/journal state for startup recovery. Delete the marker last
    // so "journal present, marker absent" cannot be produced by successful
    // cleanup.
    try {
      if (await previous.exists()) await previous.delete(recursive: true);
      if (!stagedDeletionUnresolved && await previousDeleting.exists()) {
        await previousDeleting.delete(recursive: true);
      }
      if (await journal.exists()) await journal.delete();
      await database.database.delete(
        'restore_commits',
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
    } on Exception {
      // DB and live evidence already represent one committed restore. Startup
      // recovery will finish cleanup without rolling the committed state back.
    }

    return LocalRestoreResult(
      mode: mode,
      restoredRows: restoredRows,
      keptNewerLocalRows: keptNewer,
      restoredEvidence: preparedEvidence.addedCount,
    );
  }

  Future<void> _writeJournal(
    File journal,
    String operationId,
    String previous,
    String staging,
    String phase, {
    String? previousDeleting,
    LocalRestoreMode? mode,
  }) async {
    await rejectSymlinkedPath(journal.path);
    await rejectSymlinkedPath(previous);
    await rejectSymlinkedPath(staging);
    if (previousDeleting != null) {
      await rejectSymlinkedPath(previousDeleting);
    }
    await journal.writeAsString(
      jsonEncode({
        'operationId': operationId,
        'previousPath': previous,
        'stagingPath': staging,
        ...?previousDeleting == null
            ? null
            : {'previousDeletingPath': previousDeleting},
        ...?mode == null ? null : {'mode': mode.name},
        'phase': phase,
      }),
      flush: true,
    );
  }

  Future<_BackupPackage> _readPackage(File file) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      final magic = await raf.read(_magic.length);
      if (!_listEquals(magic, _magic)) {
        throw const FormatException('Unsupported Butlerly backup format.');
      }
      final lengthBytes = await raf.read(8);
      if (lengthBytes.length != 8) {
        throw const FormatException('Incomplete Butlerly backup header.');
      }
      final metadataLength = int64FromBytes(lengthBytes);
      if (metadataLength <= 0 || metadataLength > 128 * 1024 * 1024) {
        throw const FormatException('Invalid Butlerly backup metadata length.');
      }
      final expectedHashBytes = await raf.read(64);
      if (expectedHashBytes.length != 64) {
        throw const FormatException('Incomplete Butlerly backup checksum.');
      }
      final metadataBytes = await raf.read(metadataLength);
      if (metadataBytes.length != metadataLength) {
        throw const FormatException('Incomplete Butlerly backup metadata.');
      }
      if (sha256Bytes(metadataBytes) != ascii.decode(expectedHashBytes)) {
        throw const FormatException(
          'Backup metadata integrity validation failed.',
        );
      }
      final decoded = jsonDecode(utf8.decode(metadataBytes));
      if (decoded is! Map) {
        throw const FormatException('Invalid Butlerly backup metadata.');
      }
      final metadata = decoded.cast<String, Object?>();
      final manifest = (metadata['manifest'] as Map?)?.cast<String, Object?>();
      final tables = (metadata['tables'] as Map?)?.cast<String, Object?>();
      final evidenceRaw = metadata['evidence'] as List?;
      if (manifest == null || tables == null || evidenceRaw == null) {
        throw const FormatException('Incomplete Butlerly backup metadata.');
      }
      if (manifest['format'] != format ||
          manifest['formatVersion'] != formatVersion) {
        throw const FormatException('Unsupported Butlerly backup format.');
      }
      final sourceSchema = manifest['schemaVersion'] as int?;
      if (sourceSchema == null ||
          sourceSchema < 8 ||
          sourceSchema > schemaVersion) {
        throw const FormatException(
          'Backup schema is not supported by this Butlerly build.',
        );
      }
      await _validateTablePayload(sourceSchema, tables);
      var offset = _magic.length + 8 + 64 + metadataLength;
      final descriptors = <_EvidenceDescriptor>[];
      final normalizedPaths = <String>{};
      final hashPattern = RegExp(r'^[0-9a-f]{64}$');
      for (final raw in evidenceRaw.cast<Map>()) {
        final item = raw.cast<String, Object?>();
        final relative = item['path'] as String?;
        final length = item['length'] as int?;
        final hash = item['sha256'] as String?;
        if (relative == null ||
            length == null ||
            length < 0 ||
            hash == null ||
            !hashPattern.hasMatch(hash)) {
          throw const FormatException('Invalid evidence descriptor.');
        }
        final normalized = normalizeEvidencePath(relative);
        if (!normalizedPaths.add(evidencePathKey(normalized))) {
          throw const FormatException('Invalid or duplicate evidence path.');
        }
        descriptors.add(
          _EvidenceDescriptor(
            relativePath: relative,
            length: length,
            sha256: hash,
            offset: offset,
          ),
        );
        offset += length;
      }
      if (await file.length() != offset) {
        throw const FormatException(
          'Backup file length does not match its manifest.',
        );
      }
      return _BackupPackage(
        file: file,
        manifest: manifest,
        tables: tables,
        evidence: descriptors,
      );
    } finally {
      await raf.close();
    }
  }

  Future<_PreparedEvidence> _prepareEvidence(
    _BackupPackage package, {
    required LocalRestoreMode mode,
  }) async {
    final root = await localDataManager.evidenceDirectory();
    final staging = Directory(
      '${root.path}.restore-${DateTime.now().microsecondsSinceEpoch}',
    );
    var added = 0;
    final remaps = <String, String>{};
    final expectedHashes = <String, String>{};
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      await rejectEvidenceRoot(root);
      if (mode == LocalRestoreMode.merge && await root.exists()) {
        await _copyDirectory(root, staging);
      }
      for (final item in package.evidence) {
        final normalized = normalizeEvidencePath(item.relativePath);
        final actualHash = await sha256FileRange(
          package.file,
          start: item.offset,
          endExclusive: item.offset + item.length,
        );
        if (actualHash != item.sha256) {
          throw const FormatException('Evidence integrity validation failed.');
        }
        var relative = normalized;
        var destination = File(path.join(staging.path, relative));
        if (mode == LocalRestoreMode.merge && await destination.exists()) {
          final existingHash = await sha256FileRange(destination);
          if (existingHash == item.sha256) {
            expectedHashes[evidencePathKey(relative)] = item.sha256;
            continue;
          }

          final extension = path.extension(relative);
          final base = path.basenameWithoutExtension(relative);
          final parent = path.dirname(relative);
          var attempt = 0;
          var reuseExisting = false;
          while (true) {
            final suffix = attempt == 0
                ? item.sha256
                : '${item.sha256}-$attempt';
            final name = '$base.backup-$suffix$extension';
            relative = parent == '.' ? name : path.join(parent, name);
            destination = File(path.join(staging.path, relative));
            if (!await destination.exists()) break;
            if (await sha256FileRange(destination) == item.sha256) {
              reuseExisting = true;
              break;
            }
            attempt++;
          }
          remaps[evidencePathKey(normalized)] = relative;
          expectedHashes[evidencePathKey(relative)] = item.sha256;
          if (reuseExisting) continue;
        }
        await destination.parent.create(recursive: true);
        final sink = destination.openWrite();
        try {
          await sink.addStream(
            package.file.openRead(item.offset, item.offset + item.length),
          );
          await sink.flush();
        } finally {
          await sink.close();
        }
        added++;
        expectedHashes[evidencePathKey(relative)] = item.sha256;
      }
      return _PreparedEvidence(
        directory: staging,
        addedCount: added,
        pathRemaps: remaps,
        expectedHashes: expectedHashes,
      );
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  void _migratePaymentSettlementBackupPayload(
    Map<String, Object?> tablePayload,
    int sourceSchema,
  ) {
    if (sourceSchema >= 10) return;
    if (sourceSchema < 9) return;

    final settlements =
        (tablePayload['payment_settlements'] as List? ?? const <Object?>[])
            .cast<Map>()
            .map((row) => row.cast<String, Object?>())
            .toList(growable: false);
    if (settlements.isEmpty) return;

    final transactions =
        (tablePayload['transactions'] as List? ?? const <Object?>[])
            .cast<Map>()
            .map((row) => row.cast<String, Object?>())
            .toList(growable: false);
    final transactionsById = {
      for (final row in transactions)
        if (row['id'] is String) row['id']! as String: row,
    };

    final obsoleteTransactionIds = <String>{};
    final migratedSettlements = <Map<String, Object?>>[];
    for (final settlement in settlements) {
      final transactionId = settlement['settlement_transaction_id'] as String?;
      final transaction = transactionId == null
          ? null
          : transactionsById[transactionId];
      if (transactionId == null || transaction == null) {
        throw const FormatException(
          'Payment settlement backup is missing its legacy payment record.',
        );
      }
      final amountCoefficient = transaction['amount_coefficient'];
      final amountScale = transaction['amount_scale'];
      final currency = transaction['currency'];
      final paymentDate = transaction['transaction_date'];
      if (amountCoefficient is! String ||
          amountScale is! int ||
          currency is! String ||
          paymentDate is! String) {
        throw const FormatException(
          'Legacy payment settlement has invalid payment facts.',
        );
      }

      obsoleteTransactionIds.add(transactionId);
      final migrated = <String, Object?>{...settlement}
        ..remove('settlement_transaction_id')
        ..['payment_amount_coefficient'] = amountCoefficient
        ..['payment_amount_scale'] = amountScale
        ..['payment_currency'] = currency
        ..['payment_date'] = paymentDate;
      migratedSettlements.add(migrated);
    }

    tablePayload['payment_settlements'] = migratedSettlements;
    tablePayload['transactions'] = transactions
        .where((row) => !obsoleteTransactionIds.contains(row['id']))
        .toList(growable: false);

    for (final table in const [
      'normalized_money',
      'transaction_provenances',
      'transaction_tags',
      'attachment_links',
      'review_issues',
      'suggestions',
    ]) {
      final rows = (tablePayload[table] as List? ?? const <Object?>[])
          .cast<Map>()
          .map((row) => row.cast<String, Object?>())
          .where(
            (row) => !obsoleteTransactionIds.contains(row['transaction_id']),
          )
          .toList(growable: false);
      tablePayload[table] = rows;
    }

    final statementRows =
        (tablePayload['statement_rows'] as List? ?? const <Object?>[])
            .cast<Map>()
            .map((row) => row.cast<String, Object?>())
            .map(
              (row) => obsoleteTransactionIds.contains(row['transaction_id'])
                  ? (<String, Object?>{...row}..['transaction_id'] = null)
                  : row,
            )
            .toList(growable: false);
    tablePayload['statement_rows'] = statementRows;

    final duplicateMemberships =
        (tablePayload['duplicate_candidate_group_transactions'] as List? ??
                const <Object?>[])
            .cast<Map>()
            .map((row) => row.cast<String, Object?>())
            .toList(growable: false);
    final obsoleteDuplicateGroupIds = {
      for (final row in duplicateMemberships)
        if (obsoleteTransactionIds.contains(row['transaction_id']) &&
            row['group_id'] is String)
          row['group_id']! as String,
    };
    tablePayload['duplicate_candidate_group_transactions'] =
        duplicateMemberships
            .where(
              (row) => !obsoleteDuplicateGroupIds.contains(row['group_id']),
            )
            .toList(growable: false);
    tablePayload['duplicate_candidate_groups'] =
        (tablePayload['duplicate_candidate_groups'] as List? ??
                const <Object?>[])
            .cast<Map>()
            .map((row) => row.cast<String, Object?>())
            .where((row) => !obsoleteDuplicateGroupIds.contains(row['id']))
            .toList(growable: false);

    final reconciliationCandidates =
        (tablePayload['reconciliation_candidates'] as List? ??
                const <Object?>[])
            .cast<Map>()
            .map((row) => row.cast<String, Object?>())
            .toList(growable: false);
    final obsoleteCandidateIds = {
      for (final row in reconciliationCandidates)
        if ((obsoleteTransactionIds.contains(row['receipt_transaction_id']) ||
                obsoleteTransactionIds.contains(
                  row['payment_transaction_id'],
                )) &&
            row['id'] is String)
          row['id']! as String,
    };
    tablePayload['reconciliation_candidates'] = reconciliationCandidates
        .where((row) => !obsoleteCandidateIds.contains(row['id']))
        .toList(growable: false);
    tablePayload['reconciliation_links'] =
        (tablePayload['reconciliation_links'] as List? ?? const <Object?>[])
            .cast<Map>()
            .map((row) => row.cast<String, Object?>())
            .where(
              (row) =>
                  !obsoleteCandidateIds.contains(row['candidate_id']) &&
                  !obsoleteTransactionIds.contains(
                    row['receipt_transaction_id'],
                  ) &&
                  !obsoleteTransactionIds.contains(
                    row['payment_transaction_id'],
                  ),
            )
            .toList(growable: false);

    tablePayload['entity_tombstones'] =
        (tablePayload['entity_tombstones'] as List? ?? const <Object?>[])
            .cast<Map>()
            .map((row) => row.cast<String, Object?>())
            .where(
              (row) =>
                  row['entity_type'] != 'transactions' ||
                  !obsoleteTransactionIds.contains(row['entity_id']),
            )
            .toList(growable: false);
  }

  void _applyEvidenceRemaps(
    Map<String, Object?> tablePayload,
    Map<String, String> remaps,
  ) {
    if (remaps.isEmpty) return;
    final rows = (tablePayload['evidence_items'] as List? ?? const <Object?>[])
        .cast<Map>();
    for (final raw in rows) {
      final row = raw.cast<String, Object?>();
      final current = row['local_file_name'] as String?;
      if (current == null) continue;
      final replacement =
          remaps[evidencePathKey(normalizeEvidencePath(current))];
      if (replacement != null) row['local_file_name'] = replacement;
    }
  }

  Future<void> _validateEvidenceReferences(
    Map<String, Object?> tablePayload,
    Directory evidenceRoot, {
    required Map<String, String> expectedHashes,
  }) async {
    for (final row in _tableRows(tablePayload, 'evidence_items')) {
      final raw = row['local_file_name'];
      if (raw is! String || raw.trim().isEmpty) continue;
      final relative = await validateEvidenceReferencePath(
        evidenceRoot,
        raw,
        message: 'Unsafe evidence reference.',
      );
      final evidence = File(path.join(evidenceRoot.path, relative));
      if (!await evidence.exists()) {
        throw const FormatException(
          'Backup evidence reference has no corresponding file.',
        );
      }
      final expectedHash = expectedHashes[evidencePathKey(relative)];
      if (expectedHash != null &&
          await sha256FileRange(evidence) != expectedHash) {
        throw const FormatException(
          'Backup evidence reference points to the wrong file.',
        );
      }
    }
  }

  Future<Set<String>> _protectedTransactionIds(
    DatabaseExecutor executor,
    Map<String, Object?> tablePayload,
    DateTime backupTime,
  ) async {
    final protected = <String>{};
    final spec = _specByName['transactions']!;
    final rows = (tablePayload['transactions'] as List? ?? const <Object?>[])
        .cast<Map>();
    for (final raw in rows) {
      final row = raw.cast<String, Object?>();
      final id = row['id'] as String?;
      if (id == null) continue;
      if (await _hasNewerLocalTombstone(executor, spec, row, backupTime)) {
        protected.add(id);
        continue;
      }
      final local = await executor.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (local.isNotEmpty &&
          _rowChangedAfter(local.single, spec, backupTime)) {
        protected.add(id);
      }
    }
    final newer = await executor.query(
      'transactions',
      columns: ['id'],
      where: 'created_at > ?',
      whereArgs: [backupTime.toIso8601String()],
    );
    protected.addAll(newer.map((row) => row['id']! as String));
    return protected;
  }

  bool _referencesProtectedTransaction(
    _TableSpec spec,
    Map<String, Object?> row,
    Set<String> protected,
  ) {
    if (protected.isEmpty || spec.name == 'transactions') return false;
    for (final field in const [
      'transaction_id',
      'receipt_transaction_id',
      'payment_transaction_id',
      'selected_transaction_id',
    ]) {
      final value = row[field];
      if (value is String && protected.contains(value)) return true;
    }
    return false;
  }

  Future<BackupChangeSummary> _newerLocalSummary(
    DateTime backupTime,
    Map<String, Object?> tablePayload,
  ) async {
    final cutoff = backupTime.toIso8601String();
    final transactionSpec = _specByName['transactions']!;
    final backupTransactions = _tableRows(tablePayload, 'transactions');
    final backupTransactionsByKey = {
      for (final row in backupTransactions) _rowKey(transactionSpec, row): row,
    };
    final localRowsByTable = await _portableLocalRows();
    var added = 0;
    var changed = 0;
    for (final row in localRowsByTable['transactions']!) {
      final backup = backupTransactionsByKey[_rowKey(transactionSpec, row)];
      if (backup == null) {
        added++;
      } else if (!_rowsEqual(row, backup)) {
        changed++;
      }
    }

    // Replace clears every persisted table represented in the backup. Compare
    // values as well as keys: timestamps are useful for merge precedence, but
    // they cannot detect an older divergent copy from another device.
    var master = 0;
    for (final spec in _tables) {
      if (spec.name == 'transactions') continue;
      final backupRows = _tableRows(tablePayload, spec.name);
      final backupByKey = {
        for (final row in backupRows) _rowKey(spec, row): row,
      };
      final localRows = localRowsByTable[spec.name]!;
      for (final row in localRows) {
        if (await _isSystemOwned(database.database, spec, row)) continue;
        final backup = backupByKey[_rowKey(spec, row)];
        if (backup == null || !_rowsEqual(row, backup)) {
          master++;
        }
      }
    }
    final deleted =
        Sqflite.firstIntValue(
          await database.database.rawQuery(
            "SELECT COUNT(*) FROM entity_tombstones "
            "WHERE deleted_at > ? AND entity_type NOT IN ("
            "'review_issues','suggestions','reconciliation_candidates',"
            "'duplicate_candidate_groups',"
            "'duplicate_candidate_group_transactions')",
            [cutoff],
          ),
        ) ??
        0;
    return BackupChangeSummary(
      transactionsAdded: added,
      transactionsChanged: changed,
      masterDataChanged: master,
      deletedEntities: deleted,
    );
  }

  /// Returns the rows that [LocalBackupSnapshotWriter] carries across a
  /// device boundary. Generated review/proposal state is deliberately omitted
  /// from backups, while decided workflow state remains durable and visible to
  /// inspection.
  Future<Map<String, List<Map<String, Object?>>>> _portableLocalRows() async {
    final rowsByTable = <String, List<Map<String, Object?>>>{};
    for (final spec in _tables) {
      rowsByTable[spec.name] = await database.database.query(spec.name);
    }

    rowsByTable['review_issues'] = rowsByTable['review_issues']!
        .where((row) => row['closed_at'] != null)
        .toList(growable: false);
    rowsByTable['suggestions'] = rowsByTable['suggestions']!
        .where((row) => row['decided_at'] != null)
        .toList(growable: false);

    final durableReconciliationIds = rowsByTable['reconciliation_candidates']!
        .where((row) => row['status'] != 'proposed')
        .map((row) => row['id'])
        .whereType<String>()
        .toSet();
    rowsByTable['reconciliation_candidates'] =
        rowsByTable['reconciliation_candidates']!
            .where((row) => row['status'] != 'proposed')
            .toList(growable: false);
    rowsByTable['reconciliation_links'] = rowsByTable['reconciliation_links']!
        .where((row) => durableReconciliationIds.contains(row['candidate_id']))
        .toList(growable: false);

    final duplicateGroups = rowsByTable['duplicate_candidate_groups']!;
    final durableUnresolvedDuplicateIds =
        DuplicateGroupBackupPolicy.durableUnresolvedGroupIds(
          groups: duplicateGroups,
          memberships: rowsByTable['duplicate_candidate_group_transactions']!,
          transactions: rowsByTable['transactions']!,
        );
    final portableDuplicateIds = duplicateGroups
        .where(
          (row) =>
              row['status'] != 'unresolved' ||
              DuplicateGroupBackupPolicy.hasStatementEvidence(
                row['statement_rows'],
              ) ||
              durableUnresolvedDuplicateIds.contains(row['id']),
        )
        .map((row) => row['id'])
        .whereType<String>()
        .toSet();
    rowsByTable['duplicate_candidate_groups'] = duplicateGroups
        .where((row) => portableDuplicateIds.contains(row['id']))
        .toList(growable: false);
    rowsByTable['duplicate_candidate_group_transactions'] =
        rowsByTable['duplicate_candidate_group_transactions']!
            .where((row) => portableDuplicateIds.contains(row['group_id']))
            .toList(growable: false);
    return rowsByTable;
  }

  Future<void> _validateTablePayload(
    int sourceSchema,
    Map<String, Object?> tables,
  ) async {
    final required = requiredTablesForSchema(sourceSchema);
    final missing =
        required.where((table) => !tables.containsKey(table)).toList()..sort();
    if (missing.isNotEmpty) {
      throw FormatException(
        'Backup schema $sourceSchema is missing required tables: '
        '${missing.join(', ')}.',
      );
    }
    final unknown =
        tables.keys.where((table) => !backupTableNames.contains(table)).toList()
          ..sort();
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Backup schema $sourceSchema contains unknown tables: '
        '${unknown.join(', ')}.',
      );
    }

    for (final table in backupTableNames) {
      if (!tables.containsKey(table)) continue;
      final payload = tables[table];
      if (payload is! List) {
        throw FormatException(
          'Backup schema $sourceSchema table "$table" must be a list of rows.',
        );
      }
      final keys = _validationKeysForTable(table);
      final identityKeys = table == 'entity_tombstones'
          ? const ['entity_type', 'entity_id']
          : _specByName[table]?.keys ??
                const ['entity_type', 'entity_id', 'deleted_at'];
      final schemaColumns = await _schemaColumns(table);
      final requiredRowKeys = await _requiredRowKeysForSchema(
        sourceSchema,
        table,
        schemaColumns,
      );
      final identities = <String>{};
      for (var index = 0; index < payload.length; index++) {
        final raw = payload[index];
        if (raw is! Map) {
          throw FormatException(
            'Backup schema $sourceSchema table "$table" row $index '
            'must be an object.',
          );
        }
        if (sourceSchema >= schemaVersion &&
            raw.keys.any((key) => !schemaColumns.contains(key))) {
          throw FormatException(
            'Backup schema $sourceSchema table "$table" row $index '
            'contains an unknown column.',
          );
        }
        for (final key in {...keys, ...requiredRowKeys}) {
          if (!raw.containsKey(key) || raw[key] == null) {
            throw FormatException(
              'Backup schema $sourceSchema table "$table" row $index '
              'is missing required key "$key".',
            );
          }
        }
        for (final key in identityKeys) {
          if (!raw.containsKey(key)) {
            throw FormatException(
              'Backup schema $sourceSchema table "$table" row $index '
              'is missing required key "$key".',
            );
          }
        }
        final identity = identityKeys
            .map((key) => jsonEncode(raw[key]))
            .join('|');
        if (!identities.add(identity)) {
          throw FormatException(
            'Backup schema $sourceSchema table "$table" contains duplicate '
            'identity at row $index.',
          );
        }
        _validateRowValues(sourceSchema, table, raw, index);
        _validateSemanticValues(sourceSchema, table, raw, index);
        if (table == 'entity_tombstones') {
          _validateTombstoneRow(sourceSchema, raw, index);
        }
      }
    }
    await _validateTableReferences(sourceSchema, tables);
  }

  Future<Set<String>> _schemaColumns(String table) async {
    final rows = await database.database.rawQuery(
      'PRAGMA table_info("$table")',
    );
    return rows.map((row) => row['name']).whereType<String>().toSet();
  }

  Future<Set<String>> _requiredRowKeysForSchema(
    int sourceSchema,
    String table,
    Set<String> schemaColumns,
  ) async {
    // Historical backups are intentionally validated against their historical
    // contract. Older rows may legitimately omit columns introduced later; the
    // current schema contract is enforced only for current-schema payloads.
    if (sourceSchema < schemaVersion) return const <String>{};
    final rows = await database.database.rawQuery(
      'PRAGMA table_info("$table")',
    );
    final required = rows
        .where((row) => row['notnull'] == 1 && row['dflt_value'] == null)
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
    // This field has a SQLite default, but it is part of the backup contract:
    // omitting it would let a partial row bypass built-in catalog protection.
    const protectedHistoricalFields = <String, Set<String>>{
      'merchants': {'is_built_in'},
    };
    required.addAll(protectedHistoricalFields[table] ?? const <String>{});
    return required.intersection(schemaColumns);
  }

  void _validateRowValues(int sourceSchema, String table, Map raw, int index) {
    const timestampColumns = {
      'captured_at',
      'closed_at',
      'created_at',
      'decided_at',
      'deleted_at',
      'effective_at',
      'generated_at',
      'installed_at',
      'occurred_at',
      'updated_at',
      'calculated_at',
      'retired_at',
    };
    const dateColumns = {
      'effective_date',
      'payment_date',
      'period_end',
      'period_start',
      'posting_date',
      'statement_date',
      'transaction_date',
    };
    const currencyColumns = {
      'base_currency',
      'currency',
      'from_currency',
      'payment_currency',
      'statement_balance_currency',
      'to_currency',
    };
    final coefficientPattern = RegExp(r'_coefficient$');
    final scalePattern = RegExp(r'_scale$');
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value == null) continue;
      if (value is Map || value is List) {
        throw FormatException(
          'Backup schema $sourceSchema table "$table" row $index '
          'contains a non-scalar value for "$key".',
        );
      }
      if (table == 'evidence_items' &&
          key == 'local_file_name' &&
          value is! String) {
        throw FormatException(
          'Backup schema $sourceSchema table "$table" row $index '
          'contains a non-string local evidence reference.',
        );
      }
      if (timestampColumns.contains(key) || dateColumns.contains(key)) {
        // Duplicate review records intentionally preserve malformed historical
        // timestamps so the repository can surface them as repair context.
        if (table == 'duplicate_candidate_groups' &&
            (key == 'created_at' || key == 'updated_at')) {
          continue;
        }
        if (value is! String || DateTime.tryParse(value) == null) {
          throw FormatException(
            'Backup schema $sourceSchema table "$table" row $index '
            'contains an invalid date value for "$key".',
          );
        }
      }
      if (coefficientPattern.hasMatch(key)) {
        if (value is! String) {
          throw FormatException(
            'Backup schema $sourceSchema table "$table" row $index '
            'contains an invalid decimal coefficient for "$key".',
          );
        }
        try {
          BigInt.parse(value);
        } on FormatException {
          throw FormatException(
            'Backup schema $sourceSchema table "$table" row $index '
            'contains an invalid decimal coefficient for "$key".',
          );
        }
      }
      if (scalePattern.hasMatch(key) && (value is! int || value < 0)) {
        throw FormatException(
          'Backup schema $sourceSchema table "$table" row $index '
          'contains an invalid decimal scale for "$key".',
        );
      }
      if (currencyColumns.contains(key) || key.endsWith('_currency')) {
        if (value is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
          throw FormatException(
            'Backup schema $sourceSchema table "$table" row $index '
            'contains an invalid currency value for "$key".',
          );
        }
      }
      if (key == 'confidence' || key == 'score') {
        if (value is! num || !value.isFinite || value < 0 || value > 1) {
          throw FormatException(
            'Backup schema $sourceSchema table "$table" row $index '
            'contains an invalid normalized score for "$key".',
          );
        }
      }
    }
    if (table == 'budgets') {
      final amount = raw['amount'];
      if (amount is! String) {
        throw FormatException(
          'Backup schema $sourceSchema table "$table" row $index '
          'contains an invalid decimal value for "amount".',
        );
      }
      try {
        if (!DecimalValue.parse(amount).isPositive) {
          throw const FormatException();
        }
      } on Object {
        throw FormatException(
          'Backup schema $sourceSchema table "$table" row $index '
          'contains an invalid decimal value for "amount".',
        );
      }
    }
    if (table == 'budgets') {
      final scope = raw['scope'];
      final scopeId = raw['scope_id'];
      if (scope == 'overall' && scopeId != null ||
          scope != 'overall' && scopeId == null) {
        throw FormatException(
          'Backup schema $sourceSchema table "$table" row $index '
          'contains an invalid scope identity.',
        );
      }
    }
    if (table == 'financial_profiles') {
      _validateFinancialProfileRow(sourceSchema, raw, index);
    }
  }

  void _validateFinancialProfileRow(int sourceSchema, Map raw, int index) {
    final profileId = raw['profile_id'];
    if (profileId != FinancialProfile.defaultProfileId) {
      throw FormatException(
        'Backup schema $sourceSchema table "financial_profiles" row $index '
        'contains an invalid profile identifier.',
      );
    }
    final schemaValue = raw['schema_version'];
    if (schemaValue is! int || schemaValue < 1) {
      throw FormatException(
        'Backup schema $sourceSchema table "financial_profiles" row $index '
        'contains an invalid profile schema version.',
      );
    }
    final surveyVersion = raw['survey_version'];
    if (surveyVersion is! String || surveyVersion.trim().isEmpty) {
      throw FormatException(
        'Backup schema $sourceSchema table "financial_profiles" row $index '
        'contains an invalid survey version.',
      );
    }
    _validateFinancialProfileStringList(
      sourceSchema,
      raw,
      index,
      field: 'primary_spending_categories',
      max: 3,
    );
    _validateFinancialProfileStringList(
      sourceSchema,
      raw,
      index,
      field: 'categories_to_improve',
    );
    final target = raw['monthly_savings_target'];
    final targetCurrency = raw['monthly_savings_target_currency'];
    if (target != null) {
      if (target is! String) {
        throw FormatException(
          'Backup schema $sourceSchema table "financial_profiles" row $index '
          'contains an invalid decimal value for "monthly_savings_target".',
        );
      }
      try {
        final amount = DecimalValue.parse(target);
        if (amount.isNegative ||
            amount.coefficient.abs().toString().length >
                FinancialProfile.maxSavingsTargetDigits ||
            amount.scale > FinancialProfile.maxSavingsTargetScale) {
          throw const FormatException();
        }
      } on Object {
        throw FormatException(
          'Backup schema $sourceSchema table "financial_profiles" row $index '
          'contains an invalid decimal value for "monthly_savings_target".',
        );
      }
    }
    if ((target == null) != (targetCurrency == null)) {
      throw FormatException(
        'Backup schema $sourceSchema table "financial_profiles" row $index '
        'contains an invalid savings target relationship.',
      );
    }
    final hasTarget = raw['has_monthly_savings_target'];
    if (hasTarget != null &&
        (hasTarget is! int || (hasTarget != 0 && hasTarget != 1))) {
      throw FormatException(
        'Backup schema $sourceSchema table "financial_profiles" row $index '
        'contains an invalid savings target choice.',
      );
    }
    if (target != null && hasTarget != 1) {
      throw FormatException(
        'Backup schema $sourceSchema table "financial_profiles" row $index '
        'contains a target without an enabled target choice.',
      );
    }
    final insightTypes = raw['preferred_insight_types'];
    if (insightTypes is! String) {
      throw FormatException(
        'Backup schema $sourceSchema table "financial_profiles" row $index '
        'contains invalid preferred insight types.',
      );
    }
    try {
      final decoded = jsonDecode(insightTypes);
      if (decoded is! List || decoded.any((value) => value is! String)) {
        throw const FormatException();
      }
      final allowed = _enumNames(FinancialInsightType.values);
      if (decoded.any((value) => !allowed.contains(value))) {
        throw const FormatException();
      }
    } on Object {
      throw FormatException(
        'Backup schema $sourceSchema table "financial_profiles" row $index '
        'contains invalid preferred insight types.',
      );
    }
  }

  void _validateFinancialProfileStringList(
    int sourceSchema,
    Map raw,
    int index, {
    required String field,
    int? max,
  }) {
    final value = raw[field];
    if (value is! String) {
      throw FormatException(
        'Backup schema $sourceSchema table "financial_profiles" row $index '
        'contains invalid "$field".',
      );
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List || decoded.any((item) => item is! String)) {
        throw const FormatException();
      }
      final values = decoded.cast<String>();
      if (values.any((item) => item.trim().isEmpty) ||
          (max != null && values.toSet().length > max)) {
        throw const FormatException();
      }
    } on Object {
      throw FormatException(
        'Backup schema $sourceSchema table "financial_profiles" row $index '
        'contains invalid "$field".',
      );
    }
  }

  Future<void> _validateTableReferences(
    int sourceSchema,
    Map<String, Object?> tables,
  ) async {
    // The snapshot intentionally omits catalog-owned rows; the installed
    // database reseeds those before restored user rows are applied.
    const omittedSystemTables = {
      'categories',
      'merchants',
      'reference_data',
      'tags',
    };
    final omittedSystemIds = <String, Set<String>>{
      'categories': {
        for (final row in await database.database.query(
          'categories',
          columns: ['id'],
          where: "LOWER(origin) = 'system'",
        ))
          row['id']! as String,
      },
      'merchants': {
        for (final row in await database.database.query(
          'merchants',
          columns: ['id'],
          where: 'is_built_in = 1',
        ))
          row['id']! as String,
      },
      'reference_data': {
        for (final row in await database.database.query(
          'reference_data',
          columns: ['id'],
          where: "LOWER(origin) = 'system'",
        ))
          row['id']! as String,
      },
      'tags': _builtInTagIds,
    };
    const references = <String, Map<String, String>>{
      'attachment_links': {
        'transaction_id': 'transactions',
        'evidence_id': 'evidence_items',
      },
      'categories': {'parent_id': 'categories'},
      'category_translations': {'category_id': 'categories'},
      'duplicate_candidate_group_transactions': {
        'group_id': 'duplicate_candidate_groups',
        'transaction_id': 'transactions',
      },
      'duplicate_candidate_groups': {'selected_transaction_id': 'transactions'},
      'evidence_items': {'provenance_id': 'provenances'},
      'extractions': {
        'evidence_id': 'evidence_items',
        'provenance_id': 'provenances',
      },
      'financial_statements': {
        'evidence_id': 'evidence_items',
        'payment_source_id': 'payment_sources',
      },
      'merchant_aliases': {'merchant_id': 'merchants'},
      'merchant_normalization_patterns': {'merchant_id': 'merchants'},
      'merchants': {
        'default_category_id': 'categories',
        'default_subcategory_id': 'categories',
      },
      'normalized_money': {
        'transaction_id': 'transactions',
        'exchange_rate_id': 'exchange_rates',
      },
      'payment_settlements': {'payment_source_id': 'payment_sources'},
      'reconciliation_candidates': {
        'receipt_transaction_id': 'transactions',
        'payment_transaction_id': 'transactions',
      },
      'reconciliation_links': {
        'candidate_id': 'reconciliation_candidates',
        'receipt_transaction_id': 'transactions',
        'payment_transaction_id': 'transactions',
      },
      'reference_data_translations': {'reference_data_id': 'reference_data'},
      'review_issues': {'transaction_id': 'transactions'},
      'statement_rows': {
        'statement_id': 'financial_statements',
        'transaction_id': 'transactions',
        'merchant_id': 'merchants',
        'category_id': 'categories',
        'payment_source_id': 'payment_sources',
        'subcategory_id': 'categories',
      },
      'suggestions': {
        'transaction_id': 'transactions',
        'provenance_id': 'provenances',
      },
      'tag_translations': {'tag_id': 'tags'},
      'transaction_provenances': {
        'transaction_id': 'transactions',
        'provenance_id': 'provenances',
      },
      'transaction_rules': {
        'merchant_id': 'merchants',
        'category_id': 'categories',
        'payment_source_id': 'payment_sources',
        'tag_id': 'tags',
        'assign_merchant_id': 'merchants',
        'assign_category_id': 'categories',
        'assign_payment_source_id': 'payment_sources',
        'assign_tag_id': 'tags',
        'assign_subcategory_id': 'categories',
      },
      'transaction_tags': {'transaction_id': 'transactions', 'tag_id': 'tags'},
      'transactions': {
        'payment_source_id': 'payment_sources',
        'merchant_id': 'merchants',
        'category_id': 'categories',
        'subcategory_id': 'categories',
      },
    };
    for (final entry in references.entries) {
      final rows = (tables[entry.key] as List?)?.cast<Map>() ?? const <Map>[];
      for (final raw in rows) {
        for (final reference in entry.value.entries) {
          final value = raw[reference.key];
          if (value == null) continue;
          final targetRows =
              (tables[reference.value] as List?)?.cast<Map>() ?? const <Map>[];
          if (!targetRows.any((target) => target['id'] == value)) {
            if (omittedSystemTables.contains(reference.value) &&
                omittedSystemIds[reference.value]!.contains(value)) {
              continue;
            }
            throw FormatException(
              'Backup schema $sourceSchema table "${entry.key}" references '
              'missing ${reference.value} row "$value".',
            );
          }
        }
      }
    }

    final budgetRows =
        (tables['budgets'] as List?)?.cast<Map>() ?? const <Map>[];
    for (var index = 0; index < budgetRows.length; index++) {
      final raw = budgetRows[index];
      final scope = raw['scope'];
      final scopeId = raw['scope_id'];
      if (scope == 'overall') continue;
      if (scopeId is! String || scopeId.isEmpty) {
        throw FormatException(
          'Backup schema $sourceSchema table "budgets" row $index '
          'contains an invalid scope identity.',
        );
      }
      final targetTable = scope == 'merchant' ? 'merchants' : 'categories';
      final targetIds = <String>{
        ...omittedSystemIds[targetTable]!,
        for (final target
            in (tables[targetTable] as List?)?.cast<Map>() ?? const <Map>[])
          if (target['id'] is String) target['id']! as String,
      };
      if (!targetIds.contains(scopeId)) {
        throw FormatException(
          'Backup schema $sourceSchema table "budgets" row $index '
          'references missing $targetTable row "$scopeId".',
        );
      }
    }
  }

  void _validateTombstoneRow(int sourceSchema, Map raw, int index) {
    final entityType = raw['entity_type'];
    final entityId = raw['entity_id'];
    final spec = entityType is String ? _specByName[entityType] : null;
    if (spec == null ||
        entityId == null ||
        (entityId is String && entityId.isEmpty) ||
        (entityId is! String && entityId is! num)) {
      throw FormatException(
        'Backup schema $sourceSchema table "entity_tombstones" row $index '
        'contains an unknown or malformed entity identity.',
      );
    }
    if (_keyValuesFromTombstone(spec, '$entityId') == null) {
      throw FormatException(
        'Backup schema $sourceSchema table "entity_tombstones" row $index '
        'contains an invalid entity identity.',
      );
    }
    try {
      DateTime.parse(raw['deleted_at'] as String);
    } on Object {
      throw FormatException(
        'Backup schema $sourceSchema table "entity_tombstones" row $index '
        'contains an invalid deleted_at timestamp.',
      );
    }
  }

  void _validateSemanticValues(
    int sourceSchema,
    String table,
    Map raw,
    int index,
  ) {
    final columns = _enumColumnsByTable[table];
    if (columns == null) return;
    for (final entry in columns.entries) {
      final value = raw[entry.key];
      if (value == null) continue;
      if (value is! String || !entry.value.contains(value)) {
        throw FormatException(
          'Backup schema $sourceSchema table "$table" row $index '
          'contains invalid ${entry.key} value.',
        );
      }
    }
  }

  List<String> _validationKeysForTable(String table) {
    // SQLite permits exchange_rate_id to be NULL for user-entered
    // normalization. It participates in the lookup key for merge semantics,
    // but is not a required payload identity field.
    if (table == 'normalized_money') return const ['transaction_id'];
    return _specByName[table]?.keys ??
        const ['entity_type', 'entity_id', 'deleted_at'];
  }

  Future<int> _applyBackupTombstones(
    Transaction tx,
    Map<String, Object?> tablePayload,
    DateTime backupTime,
  ) async {
    var kept = 0;
    final tombstones =
        (tablePayload['entity_tombstones'] as List? ?? const <Object?>[])
            .cast<Map>();
    for (final raw in tombstones) {
      final tombstone = raw.cast<String, Object?>();
      final entityType = tombstone['entity_type'] as String?;
      final entityId = tombstone['entity_id'];
      final spec = entityType == null ? null : _specByName[entityType];
      if (spec == null || entityId == null) {
        throw const FormatException('Invalid backup tombstone.');
      }
      final values = _keyValuesFromTombstone(spec, '$entityId');
      if (values == null) {
        throw const FormatException('Invalid backup tombstone identity.');
      }
      final localRows = await _queryByKeys(tx, spec, values);
      if (localRows.isNotEmpty &&
          await _isSystemOwned(tx, spec, localRows.single)) {
        continue;
      }
      if (localRows.isNotEmpty &&
          _rowChangedAfter(localRows.single, spec, backupTime)) {
        kept++;
        continue;
      }
      final localTombstone = await _findTombstone(tx, spec.name, '$entityId');
      if (localTombstone != null &&
          _tombstoneTime(localTombstone).compareTo(_tombstoneTime(tombstone)) >=
              0) {
        kept++;
        continue;
      }
      if (localRows.isNotEmpty) await _deleteByKeys(tx, spec, values);
      await tx.insert(
        'entity_tombstones',
        tombstone,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return kept;
  }

  Future<Map<String, Object?>?> _findTombstone(
    DatabaseExecutor tx,
    String entityType,
    String entityId,
  ) async {
    final rows = await tx.query(
      'entity_tombstones',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  DateTime _tombstoneTime(Map<String, Object?> row) =>
      DateTime.parse(row['deleted_at']! as String).toUtc();

  Future<bool> _hasNewerLocalTombstone(
    DatabaseExecutor tx,
    _TableSpec spec,
    Map<String, Object?> row,
    DateTime backupTime,
  ) async {
    final id = _tombstoneId(spec, row);
    if (id == null) return false;
    final results = await tx.query(
      'entity_tombstones',
      where: 'entity_type = ? AND entity_id = ? AND deleted_at > ?',
      whereArgs: [spec.name, id, backupTime.toIso8601String()],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  Future<void> _clearTombstoneForRestoredRow(
    Transaction tx,
    _TableSpec spec,
    Map<String, Object?> row,
  ) async {
    final id = _tombstoneId(spec, row);
    if (id == null) return;
    await tx.delete(
      'entity_tombstones',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [spec.name, id],
    );
  }

  String? _tombstoneId(_TableSpec spec, Map<String, Object?> row) {
    final values = spec.keys.map((key) => row[key]).toList();
    if (values.any((value) => value == null)) return null;
    return values.map((value) => '$value').join('|');
  }

  List<Object?>? _keyValuesFromTombstone(_TableSpec spec, String id) {
    if (spec.keys.length == 1) return [id];
    final values = id.split('|');
    return values.length == spec.keys.length ? values : null;
  }

  Future<Map<String, Object?>?> _findRow(
    DatabaseExecutor tx,
    _TableSpec spec,
    Map<String, Object?> row,
  ) async {
    final values = spec.keys.map((key) => row[key]).toList(growable: false);
    final rows = await _queryByKeys(tx, spec, values);
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> _queryByKeys(
    DatabaseExecutor tx,
    _TableSpec spec,
    List<Object?> values,
  ) {
    final where = <String>[];
    final args = <Object?>[];
    for (var index = 0; index < spec.keys.length; index++) {
      final value = values[index];
      if (value == null) {
        where.add('${spec.keys[index]} IS NULL');
      } else {
        where.add('${spec.keys[index]} = ?');
        args.add(value);
      }
    }
    return tx.query(
      spec.name,
      where: where.join(' AND '),
      whereArgs: args,
      limit: 1,
    );
  }

  Future<void> _deleteByKeys(
    DatabaseExecutor tx,
    _TableSpec spec,
    List<Object?> values,
  ) async {
    final where = <String>[];
    final args = <Object?>[];
    for (var index = 0; index < spec.keys.length; index++) {
      final value = values[index];
      if (value == null) {
        where.add('${spec.keys[index]} IS NULL');
      } else {
        where.add('${spec.keys[index]} = ?');
        args.add(value);
      }
    }
    await tx.delete(spec.name, where: where.join(' AND '), whereArgs: args);
  }

  Future<void> _upsertRow(
    Transaction tx,
    _TableSpec spec,
    Map<String, Object?> row,
  ) async {
    if (spec.mergeUnion) {
      await tx.insert(
        spec.name,
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return;
    }
    final existing = await _findRow(tx, spec, row);
    if (existing == null) {
      await tx.insert(spec.name, row);
      return;
    }
    final values = spec.keys.map((key) => row[key]).toList(growable: false);
    final where = <String>[];
    final args = <Object?>[];
    for (var index = 0; index < spec.keys.length; index++) {
      final value = values[index];
      if (value == null) {
        where.add('${spec.keys[index]} IS NULL');
      } else {
        where.add('${spec.keys[index]} = ?');
        args.add(value);
      }
    }
    await tx.update(
      spec.name,
      row,
      where: where.join(' AND '),
      whereArgs: args,
    );
  }

  /// Historical snapshots ordered non-root categories by ID, which is not a
  /// valid insertion order for every multi-level hierarchy. Restore the
  /// payload topologically while leaving references to installed system
  /// categories ready to insert immediately.
  List<Map<String, Object?>> _orderCategories(List<Map<String, Object?>> rows) {
    final byId = <String, Map<String, Object?>>{
      for (final row in rows)
        if (row['id'] is String) row['id']! as String: row,
    };
    final pending = rows.toList(growable: true);
    final ordered = <Map<String, Object?>>[];
    final inserted = <String>{};
    while (pending.isNotEmpty) {
      var progressed = false;
      for (var index = pending.length - 1; index >= 0; index--) {
        final row = pending[index];
        final parentId = row['parent_id'];
        final parentIsInPayload =
            parentId is String && byId.containsKey(parentId);
        if (parentIsInPayload && !inserted.contains(parentId)) continue;
        pending.removeAt(index);
        ordered.add(row);
        if (row['id'] is String) inserted.add(row['id']! as String);
        progressed = true;
      }
      if (!progressed) {
        throw const FormatException(
          'Backup contains a cyclic category hierarchy.',
        );
      }
    }
    return ordered;
  }

  bool _rowChangedAfter(
    Map<String, Object?> row,
    _TableSpec spec,
    DateTime cutoff,
  ) {
    for (final field in [spec.updatedAt, spec.createdAt]) {
      if (field == null) continue;
      final value = row[field];
      if (value is! String || value.isEmpty) continue;
      final parsed = DateTime.tryParse(value)?.toUtc();
      if (parsed != null && parsed.isAfter(cutoff)) return true;
    }
    return false;
  }

  bool _rowsEqual(Map<String, Object?> left, Map<String, Object?> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  String _rowKey(_TableSpec spec, Map<String, Object?> row) =>
      spec.keys.map((key) => jsonEncode(row[key])).join('|');

  Future<bool> _isSystemOwned(
    DatabaseExecutor executor,
    _TableSpec spec,
    Map<String, Object?> row,
  ) async {
    switch (spec.name) {
      case 'categories':
        return '${row['origin']}'.toLowerCase() == 'system';
      case 'merchants':
        return row['is_built_in'] == 1;
      case 'tags':
        return _builtInTagIds.contains(row['id']);
      case 'category_translations':
        final parent = await executor.query(
          'categories',
          columns: ['origin'],
          where: 'id = ?',
          whereArgs: [row['category_id']],
          limit: 1,
        );
        return parent.isNotEmpty &&
            '${parent.single['origin']}'.toLowerCase() == 'system';
      case 'tag_translations':
        return _builtInTagIds.contains(row['tag_id']);
      case 'reference_data':
        return '${row['origin']}'.toLowerCase() == 'system';
      case 'reference_data_translations':
        final parent = await executor.query(
          'reference_data',
          columns: ['origin'],
          where: 'id = ?',
          whereArgs: [row['reference_data_id']],
          limit: 1,
        );
        return parent.isNotEmpty &&
            '${parent.single['origin']}'.toLowerCase() == 'system';
      default:
        return false;
    }
  }

  List<Map<String, Object?>> _tableRows(
    Map<String, Object?> tablePayload,
    String table,
  ) {
    return (tablePayload[table] as List? ?? const <Object?>[])
        .cast<Map>()
        .map((row) => row.cast<String, Object?>())
        .toList(growable: false);
  }

  Future<Set<String>> _durableUnresolvedDuplicateGroupIdsFromDatabase(
    DatabaseExecutor executor,
  ) async {
    final groups = await executor.query(
      'duplicate_candidate_groups',
      where: "status = 'unresolved'",
    );
    if (groups.isEmpty) return const <String>{};
    return DuplicateGroupBackupPolicy.durableUnresolvedGroupIds(
      groups: groups,
      memberships: await executor.query(
        'duplicate_candidate_group_transactions',
      ),
      transactions: await executor.query(
        'transactions',
        columns: [
          'id',
          'transaction_date',
          'amount_coefficient',
          'amount_scale',
          'currency',
          'direction',
          'status',
        ],
      ),
    );
  }

  Future<void> _purgeGeneratedWorkflowState(
    Transaction tx, {
    Set<String> preserveDuplicateGroupIds = const <String>{},
  }) async {
    final duplicateGroupCondition = preserveDuplicateGroupIds.isEmpty
        ? (
            where:
                "status = 'unresolved' AND "
                "(statement_rows IS NULL OR statement_rows = '[]')",
            args: <Object?>[],
          )
        : (
            where:
                "status = 'unresolved' AND "
                "(statement_rows IS NULL OR statement_rows = '[]') AND "
                "id NOT IN (${List.filled(preserveDuplicateGroupIds.length, '?').join(', ')})",
            args: preserveDuplicateGroupIds.toList(growable: false),
          );
    await tx.delete('review_issues', where: 'closed_at IS NULL');
    await tx.delete('suggestions', where: 'decided_at IS NULL');
    await tx.delete('reconciliation_candidates', where: "status = 'proposed'");
    await tx.rawDelete(
      'DELETE FROM duplicate_candidate_group_transactions '
      'WHERE group_id IN ('
      "SELECT id FROM duplicate_candidate_groups "
      'WHERE ${duplicateGroupCondition.where}'
      ')',
      duplicateGroupCondition.args,
    );
    await tx.delete(
      'duplicate_candidate_groups',
      where: duplicateGroupCondition.where,
      whereArgs: duplicateGroupCondition.args,
    );
    await tx.delete(
      'entity_tombstones',
      where:
          "entity_type IN ('review_issues', 'suggestions', "
          "'reconciliation_candidates', 'duplicate_candidate_groups', "
          "'duplicate_candidate_group_transactions')",
    );
  }

  Future<void> _clearPortableState(Transaction tx) async {
    // Translations and reference data are catalog children. Keep current
    // system-owned rows so a restore cannot pin an obsolete bundled catalog,
    // while removing all user-owned rows before restoring the backup payload.
    await tx.delete(
      'category_translations',
      where:
          'category_id IN ('
          "SELECT id FROM categories WHERE LOWER(origin) != 'system'"
          ')',
    );
    await tx.delete(
      'tag_translations',
      where:
          'tag_id IN ('
          "SELECT id FROM tags WHERE id NOT IN ("
          "'tag.business','tag.personal','tag.reimbursable',"
          "'tag.tax_related','tag.travel','tag.recurring','tag.subscription'"
          ')'
          ')',
    );
    await tx.delete(
      'reference_data_translations',
      where:
          'reference_data_id IN ('
          "SELECT id FROM reference_data WHERE LOWER(origin) != 'system'"
          ')',
    );
    await tx.delete('reference_data', where: "LOWER(origin) != 'system'");

    final childFirst = <String>[
      'budgets',
      'transaction_rules',
      'merchant_normalization_patterns',
      'merchant_aliases',
      'duplicate_candidate_group_transactions',
      'duplicate_candidate_groups',
      'reconciliation_links',
      'reconciliation_candidates',
      'review_issues',
      'suggestions',
      'attachment_links',
      'extractions',
      'statement_rows',
      'financial_statements',
      'evidence_items',
      'transaction_tags',
      'transaction_provenances',
      'normalized_money',
      'payment_settlements',
      'transactions',
      'exchange_rates',
      'provenances',
      'analysis_rule_configurations',
      'analysis_rule_activations',
      'recurring_pattern_decisions',
      'payment_sources',
      'user_preferences',
      'financial_profiles',
    ];
    for (final table in childFirst) {
      await tx.delete(table);
    }
    await tx.delete('merchants', where: 'is_built_in = 0');
    await tx.delete('categories', where: "LOWER(origin) != 'system'");
    await tx.delete(
      'tags',
      where:
          'id NOT IN ('
          "'tag.business','tag.personal','tag.reimbursable',"
          "'tag.tax_related','tag.travel','tag.recurring','tag.subscription'"
          ')',
    );
    await tx.delete('entity_tombstones');
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await rejectEvidenceRoot(source);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      await rejectEvidenceLink(entity);
      final relative = path.relative(entity.path, from: source.path);
      final target = path.join(destination.path, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        final file = File(target);
        await file.parent.create(recursive: true);
        await entity.copy(file.path);
      }
    }
  }

  bool _listEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
