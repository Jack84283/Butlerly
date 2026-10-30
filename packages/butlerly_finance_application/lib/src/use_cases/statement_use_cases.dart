import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../analysis/invalidation.dart';
import '../dto/transaction_dto.dart';
import '../result/application_result.dart';
import 'classification_use_cases.dart';
import 'duplicate_transaction_use_cases.dart';
import 'merchant_review_use_cases.dart';
import 'reconciliation_use_cases.dart';
import 'statement_intake_policy.dart';
import 'transaction_use_cases.dart';
import 'transaction_rule_use_cases.dart';

const statementSourceFingerprintPrefix = 'statement-sha256:';

final class StatementImportSummary {
  const StatementImportSummary({
    required this.imported,
    required this.needsReview,
    required this.possibleDuplicates,
    required this.failed,
  });
  final int imported;
  final int needsReview;
  final int possibleDuplicates;
  final int failed;
}

final class StatementReviewException {
  const StatementReviewException({
    required this.statementId,
    required this.rowId,
    required this.description,
    required this.originalText,
    required this.reason,
  });

  final String statementId;
  final String rowId;
  final String? description;
  final String originalText;
  final String? reason;
}

final class StatementImportAssessment {
  const StatementImportAssessment({
    required this.candidateCount,
    required this.aggregateAmount,
    required this.currency,
    required this.lowConfidenceCount,
    required this.possibleDuplicateCount,
    required this.duplicateCheckUnavailableCount,
    required this.invalidCount,
  });
  final int candidateCount;
  final String? aggregateAmount;
  final String? currency;
  final int lowConfidenceCount;
  final int possibleDuplicateCount;
  final int duplicateCheckUnavailableCount;
  final int invalidCount;
}

final class _PreparedStatementTransaction {
  const _PreparedStatementTransaction({required this.value, this.proposal});

  final Transaction value;
  final ClassificationProposal? proposal;
}

final class StatementServices {
  const StatementServices(
    this.statements,
    this.transactions,
    this.workflow,
    this.clock, {
    this.evidence,
    this.applyRules,
    this.merchants,
    this.invalidateAnalysis,
    this.consistencyGate,
    required this.duplicateGroups,
    required this.duplicateChecker,
    this.classifier,
    this.intakePolicy = const StatementIntakePolicy(),
  });
  final StatementIntakePolicy intakePolicy;
  final StatementRepository statements;
  final TransactionRepository transactions;
  final StatementWorkflowRepository workflow;
  final ApplicationClock clock;
  final EvidenceRepository? evidence;
  final ApplyTransactionRules? applyRules;
  final MerchantRepository? merchants;
  final InvalidateAnalysis? invalidateAnalysis;
  final AnalysisConsistencyGate? consistencyGate;
  final DuplicateCandidateGroupRepository duplicateGroups;
  final DuplicateTransactionChecker duplicateChecker;
  final ProposeTransactionClassification? classifier;

  Future<ApplicationResult<StatementImportAssessment>> assessBatch(
    FinancialStatement statement,
    List<StatementRow> rows,
    String paymentSourceId,
  ) => _runExclusive(
    () => runApplication('assess statement batch', () async {
      if (statement.paymentSourceId != null &&
          statement.paymentSourceId != paymentSourceId) {
        throw const DomainValidationException(
          code: DomainErrorCode.invalidState,
          field: 'paymentSourceId',
          message: 'The selected payment source does not match the statement.',
        );
      }
      final possibleDuplicateRowIds = <String>{
        ..._sameBatchDuplicateRowIds(rows),
      };
      var duplicateCheckUnavailableCount = 0;
      for (final row in rows) {
        if (row.amount == null ||
            row.currency == null ||
            row.transactionDate == null ||
            row.direction == null) {
          continue;
        }
        final result = await duplicates(
          row,
          excludeTransactionId: _transactionIdForRow(row),
        );
        if (result case ApplicationSuccess<DuplicateTransactionCheckResult>(
          value: final value,
        ) when value.candidates.isNotEmpty) {
          possibleDuplicateRowIds.add(row.id);
        } else if (result
            is ApplicationFailure<DuplicateTransactionCheckResult>) {
          duplicateCheckUnavailableCount++;
        }
      }
      final valid = rows.where(
        (row) =>
            row.amount != null &&
            row.currency != null &&
            row.transactionDate != null &&
            row.direction != null,
      );
      final currencies = valid.map((row) => row.currency!).toSet();
      String? aggregate;
      String? currency;
      if (currencies.length == 1) {
        currency = currencies.single;
        aggregate = DecimalValue.sum(
          valid.map((row) => DecimalValue.parse(row.amount!)),
        ).toString();
      }
      return StatementImportAssessment(
        candidateCount: rows.length,
        aggregateAmount: aggregate,
        currency: currency,
        lowConfidenceCount: rows
            .where((row) => intakePolicy.needsConfidenceReview(row.confidence))
            .length,
        possibleDuplicateCount: possibleDuplicateRowIds.length,
        duplicateCheckUnavailableCount: duplicateCheckUnavailableCount,
        invalidCount: rows.length - valid.length,
      );
    }),
  );

  Future<ApplicationResult<StatementImportSummary>> importBatch(
    FinancialStatement statement,
    List<StatementRow> rows,
    String paymentSourceId,
  ) => _runExclusive(
    () => runApplication('import statement batch', () async {
      if (statement.paymentSourceId != null &&
          statement.paymentSourceId != paymentSourceId) {
        throw const DomainValidationException(
          code: DomainErrorCode.invalidState,
          field: 'paymentSourceId',
          message: 'The selected payment source does not match the statement.',
        );
      }
      var imported = 0;
      var needsReview = 0;
      var possibleDuplicates = 0;
      var failed = 0;
      final duplicateRowIds = <String>{};
      final duplicateMetadataRowIds = <String>{};
      final duplicateCandidateIdsByRow = <String, List<String>>{};
      final exceptionReasons = <String, String>{};
      final sameBatchDuplicateRows = _sameBatchDuplicateRowIds(rows);
      final persistedRows = {
        for (final value in await statements.listRows(statement.id))
          value.id: value,
      };
      final prepared = <StatementRowTransaction>[];
      for (final row in rows) {
        if (row.amount == null ||
            row.currency == null ||
            row.transactionDate == null ||
            row.direction == null) {
          failed++;
          exceptionReasons[row.id] = 'statementInvalidRow';
          continue;
        }
        final transactionId = _transactionIdForRow(row);
        final persisted = persistedRows[row.id];
        final committed =
            persisted?.status == StatementRowStatus.saved ||
            persisted?.status == StatementRowStatus.linked ||
            row.status == StatementRowStatus.saved ||
            row.status == StatementRowStatus.linked;
        if (persisted?.status == StatementRowStatus.deferred ||
            persisted?.status == StatementRowStatus.skipped) {
          // A retry must not reopen an explicit review decision. The metadata
          // repair below removes the row from any pending duplicate group while
          // preserving the user's disposition and retained candidate evidence.
          duplicateMetadataRowIds.add(row.id);
          continue;
        }
        if (!committed &&
            persisted?.status == StatementRowStatus.unresolved &&
            persisted?.reviewReason == 'statementDuplicateCandidate') {
          final candidateIds = await _candidateTransactionIdsForRow(row);
          if (candidateIds.isNotEmpty) {
            // A pending statement duplicate may retain the existing candidate ID
            // as evidence, but it is not linked until the user explicitly chooses
            // Link, Skip/Defer, or Create New.
            possibleDuplicates++;
            duplicateRowIds.add(row.id);
            duplicateCandidateIdsByRow[row.id] = candidateIds;
            exceptionReasons[row.id] = 'statementDuplicateCandidate';
            continue;
          }
        }
        final existingTransactionId =
            (persisted?.reviewReason == 'statementDuplicateCandidate'
                ? transactionId
                : persisted?.transactionId) ??
            (committed ? row.transactionId : null) ??
            transactionId;
        final existing = await transactions.findById(
          TransactionId(existingTransactionId),
        );
        if (existing != null) {
          // A retry of a committed row is idempotent even if a newer matching
          // transaction now exists. Repair only the duplicate metadata; never
          // reopen the statement row or overwrite the user's corrections.
          duplicateMetadataRowIds.add(row.id);
          continue;
        }
        if (sameBatchDuplicateRows.contains(row.id)) {
          possibleDuplicates++;
          duplicateRowIds.add(row.id);
          exceptionReasons[row.id] = 'statementDuplicateCandidate';
          continue;
        }
        final duplicateResult = await duplicates(
          row,
          excludeTransactionId: transactionId,
        );
        if (duplicateResult
            case ApplicationSuccess<DuplicateTransactionCheckResult>(
              value: final duplicate,
            ) when duplicate.candidates.isNotEmpty) {
          // Batch import is exception-first. A suspected duplicate remains a
          // pending statement row until the user explicitly links it or chooses
          // to create a separate transaction from the row review flow.
          possibleDuplicates++;
          duplicateRowIds.add(row.id);
          duplicateCandidateIdsByRow[row.id] = duplicate.candidates
              .map((candidate) => candidate.transaction.id)
              .toList(growable: false);
          exceptionReasons[row.id] = 'statementDuplicateCandidate';
          continue;
        }
        if (duplicateResult
            is ApplicationFailure<DuplicateTransactionCheckResult>) {
          failed++;
          exceptionReasons[row.id] = 'statementDuplicateCheckUnavailable';
          continue;
        }
        final transaction = await _prepareTransaction(
          row,
          paymentSourceId,
          allowCreateNew: true,
        );
        final now = clock.now();
        prepared.add(
          StatementRowTransaction(
            row: _copy(
              row,
              status: StatementRowStatus.saved,
              transactionId: transaction.value.id.value,
              dispositionReason: 'createNew',
              updatedAt: now,
            ),
            transaction: transaction.value,
          ),
        );
        imported++;
        if (intakePolicy.needsConfidenceReview(row.confidence) ||
            row.status == StatementRowStatus.unresolved) {
          needsReview++;
        }
      }
      if (prepared.isNotEmpty) await _invalidateAnalysis();
      await workflow.saveRowTransactions(prepared);
      for (final entry in exceptionReasons.entries) {
        final row = rows.where((value) => value.id == entry.key).firstOrNull;
        if (row == null) continue;
        try {
          await _markStatementException(row, entry.value);
        } on Object {
          // Keep the committed summary, but surface that the exception marker
          // itself could not be persisted for a later retry.
          failed++;
        }
      }
      for (final row in rows) {
        if (!duplicateRowIds.contains(row.id) &&
            !duplicateMetadataRowIds.contains(row.id)) {
          continue;
        }
        try {
          final repairRow = duplicateMetadataRowIds.contains(row.id)
              ? persistedRows[row.id] ?? row
              : row;
          final pendingRows = duplicateRowIds
              .map((id) => rows.where((value) => value.id == id).firstOrNull)
              .whereType<StatementRow>()
              .where(
                (value) =>
                    value.amount != null &&
                    value.currency != null &&
                    value.transactionDate != null &&
                    value.direction != null &&
                    repairRow.amount != null &&
                    repairRow.currency != null &&
                    repairRow.transactionDate != null &&
                    repairRow.direction != null &&
                    _duplicateKeyForRow(value) ==
                        _duplicateKeyForRow(repairRow),
              )
              .map(
                (value) => DuplicateCandidateStatementRow(
                  statementId: value.statementId,
                  rowId: value.id,
                ),
              )
              .toList(growable: false);
          await _repairDuplicateReview(
            repairRow,
            candidateTransactionIds: duplicateCandidateIdsByRow[repairRow.id],
            pendingStatementRows: duplicateRowIds.contains(row.id)
                ? pendingRows
                : const [],
          );
        } on Object {
          // Valid rows have already been committed. Return their summary and
          // expose this metadata failure instead of hiding committed work in an
          // application failure that invites an unsafe retry.
          failed++;
        }
      }
      return StatementImportSummary(
        imported: imported,
        needsReview: needsReview,
        possibleDuplicates: possibleDuplicates,
        failed: failed,
      );
    }),
  );

  Future<ApplicationResult<StatementImportSummary>> importRows(
    FinancialStatement statement,
    List<StatementRow> rows,
    String paymentSourceId,
  ) => importBatch(statement, rows, paymentSourceId);

  Future<ApplicationResult<DuplicateTransactionCheckResult>> duplicates(
    StatementRow row, {
    String? excludeTransactionId,
  }) async {
    if (row.amount == null ||
        row.currency == null ||
        row.transactionDate == null ||
        row.direction == null) {
      return const ApplicationSuccess(DuplicateTransactionCheckResult([]));
    }
    return duplicateChecker(
      DuplicateTransactionCheckCommand(
        transactionDate: row.transactionDate!.toIso8601String().substring(
          0,
          10,
        ),
        amount: row.amount!,
        currency: row.currency!,
        direction: _directionForRow(row),
        paymentSourceId: row.paymentSourceId,
        merchantId: row.merchantId,
        excludeTransactionId: excludeTransactionId,
      ),
    );
  }

  Future<ApplicationResult<void>> create(
    FinancialStatement statement,
    List<StatementRow> rows,
  ) => _runExclusive(
    () => runApplication(
      'create statement',
      () => statements.saveStatementWithRows(statement, rows),
    ),
  );

  /// Replaces a technical OCR failure only when the persisted statement still
  /// has the same revision and no user-authored rows. This keeps retry from
  /// overwriting corrections made while OCR was running.
  Future<ApplicationResult<void>> retryTechnicalFailure({
    required FinancialStatement expected,
    required FinancialStatement updated,
    required List<StatementRow> rows,
    Extraction? extraction,
  }) => _runExclusive(
    () => runApplication('retry statement OCR', () async {
      final current = await statements.findStatement(expected.id);
      if (current == null || current.updatedAt != expected.updatedAt) {
        throw const RepositoryException(
          RepositoryFailureCode.constraint,
          'retry statement OCR: statement changed',
        );
      }
      final existingRows = await statements.listRows(expected.id);
      if (existingRows.isNotEmpty) {
        throw const RepositoryException(
          RepositoryFailureCode.constraint,
          'retry statement OCR: statement rows changed',
        );
      }
      if (extraction != null) {
        final evidenceRepository = evidence;
        if (evidenceRepository == null) {
          throw const RepositoryException(
            RepositoryFailureCode.unavailable,
            'retry statement OCR: evidence repository',
          );
        }
        await evidenceRepository.saveExtraction(extraction);
      }
      await statements.saveStatementWithRows(updated, rows);
    }),
  );

  Future<ApplicationResult<List<FinancialStatement>>> list({
    bool includeArchived = false,
  }) => _runExclusive(
    () => runApplication(
      'list statements',
      () => statements.listStatements(includeArchived: includeArchived),
    ),
  );

  /// Finds a previously captured statement by immutable source bytes.
  ///
  /// The fingerprint is stored in evidence provenance, so this remains stable
  /// across process restarts without adding a schema migration.
  Future<ApplicationResult<FinancialStatement?>> findBySourceFingerprint(
    String fingerprint,
  ) => _runExclusive(
    () => runApplication('find statement source', () async {
      final sourceId = statementSourceFingerprintPrefix + fingerprint;
      for (final item in await statements.listStatements(
        includeArchived: true,
      )) {
        final evidenceItem = evidence == null
            ? null
            : await evidence!.findById(EvidenceId(item.evidenceId));
        if (evidenceItem?.provenance.sourceId == sourceId) return item;
      }
      return null;
    }),
  );

  Future<ApplicationResult<List<StatementReviewException>>>
  reviewExceptions() => _runExclusive(
    () => runApplication('list statement review exceptions', () async {
      final result = <StatementReviewException>[];
      final duplicateReferences = {
        for (final group in await duplicateGroups.list())
          for (final reference in group.statementRows) reference.canonical,
      };
      for (final statement in await statements.listStatements()) {
        for (final row in await statements.listRows(statement.id)) {
          if (row.status != StatementRowStatus.unresolved ||
              (row.reviewReason == 'statementDuplicateCandidate' &&
                  duplicateReferences.contains(
                    '${row.statementId}:${row.id}',
                  ))) {
            continue;
          }
          result.add(
            StatementReviewException(
              statementId: statement.id,
              rowId: row.id,
              description: row.description,
              originalText: row.originalText,
              reason: row.reviewReason,
            ),
          );
        }
      }
      return List.unmodifiable(result);
    }),
  );

  Future<ApplicationResult<List<StatementRow>>> rows(String id) =>
      _runExclusive(
        () => runApplication(
          'list statement rows',
          () => statements.listRows(id),
        ),
      );

  Future<ApplicationResult<String?>> paymentSourceId(String statementId) =>
      _runExclusive(
        () => runApplication('read statement payment source', () async {
          final statement = await statements.findStatement(statementId);
          if (statement == null) {
            throw const RepositoryException(
              RepositoryFailureCode.notFound,
              'read statement payment source',
            );
          }
          return statement.paymentSourceId;
        }),
      );

  Future<ApplicationResult<void>> addRows(List<StatementRow> rows) =>
      _runExclusive(
        () => runApplication(
          'add statement rows',
          () => statements.saveRows(rows),
        ),
      );

  Future<ApplicationResult<void>> assignSource(String id, String sourceId) =>
      _runExclusive(
        () => runApplication(
          'assign statement payment source',
          () => statements.assignPaymentSource(id, sourceId, clock.now()),
        ),
      );

  Future<ApplicationResult<bool>> canDeleteStatement(String id) =>
      _runExclusive(
        () => runApplication('check statement deletion eligibility', () async {
          final statement = await statements.findStatement(id);
          if (statement == null) {
            throw const RepositoryException(
              RepositoryFailureCode.notFound,
              'check statement deletion eligibility',
            );
          }
          return statements.canDeleteStatement(id);
        }),
      );

  Future<ApplicationResult<EvidenceItem?>> deleteStatement(String id) =>
      _runExclusive(
        () => runApplication('delete unprocessed statement', () async {
          final statement = await statements.findStatement(id);
          if (statement == null) {
            throw const RepositoryException(
              RepositoryFailureCode.notFound,
              'delete statement',
            );
          }
          if (!await statements.canDeleteStatement(id)) {
            throw const DomainValidationException(
              code: DomainErrorCode.invalidState,
              field: 'statement',
              message: 'A processed statement cannot be deleted safely.',
            );
          }
          final evidenceRepository = evidence;
          final ownedEvidence = evidenceRepository == null
              ? null
              : await evidenceRepository.findById(
                  EvidenceId(statement.evidenceId),
                );
          await _invalidateAnalysis();
          await _removeStatementDuplicateReferences(id);
          await statements.removeStatement(id);
          return ownedEvidence;
        }),
      );

  // Abandonment currently reuses the relationship-safe deletion primitive;
  // keeping the operation separate at the application boundary preserves the
  // distinct pre-persistence user intent without duplicating cleanup logic.
  Future<ApplicationResult<EvidenceItem?>> abandonImport(String id) =>
      deleteStatement(id);

  @Deprecated('Use deleteStatement for stored statements.')
  Future<ApplicationResult<EvidenceItem?>> deleteUnprocessed(String id) =>
      deleteStatement(id);

  Future<ApplicationResult<void>> setDisposition(
    StatementRow row,
    StatementRowStatus status,
  ) => _runExclusive(
    () => runApplication('update statement row', () async {
      final previous =
          status == StatementRowStatus.skipped &&
              row.status != StatementRowStatus.skipped
          ? row.status
          : row.status == StatementRowStatus.skipped
          ? row.statusBeforeSkip
          : null;
      final updated = _copy(
        row,
        status: status,
        statusBeforeSkip: previous,
        clearStatusBeforeSkip:
            row.status == StatementRowStatus.skipped &&
            status != StatementRowStatus.skipped,
        clearTransactionId:
            status == StatementRowStatus.deferred ||
            status == StatementRowStatus.skipped,
        updatedAt: clock.now(),
      );
      await _invalidateAnalysis();
      await statements.updateRow(updated);
      final hasDuplicateFacts =
          updated.amount != null &&
          updated.currency != null &&
          updated.transactionDate != null &&
          updated.direction != null;
      if (status == StatementRowStatus.unresolved) {
        if (hasDuplicateFacts) {
          final activeIds = await duplicateGroups
              .findActiveTransactionIdsForKey(_duplicateKeyForRow(updated));
          if (activeIds.isNotEmpty) {
            await _repairDuplicateReview(
              updated,
              pendingStatementRows: [
                DuplicateCandidateStatementRow(
                  statementId: updated.statementId,
                  rowId: updated.id,
                ),
              ],
            );
          }
        }
      } else if (hasDuplicateFacts) {
        await _repairDuplicateReview(updated);
      }
    }),
  );

  Future<ApplicationResult<void>> toggleSkipRestore(StatementRow row) {
    final target = row.status == StatementRowStatus.skipped
        ? row.statusBeforeSkip ?? StatementRowStatus.unresolved
        : StatementRowStatus.skipped;
    return setDisposition(row, target);
  }

  Future<ApplicationResult<void>> correct(StatementRow row) => _runExclusive(
    () => runApplication('correct statement row', () async {
      final previous = (await statements.listRows(
        row.statementId,
      )).where((value) => value.id == row.id).firstOrNull;
      await _invalidateAnalysis();
      await statements.updateRow(row);
      if (previous == null) {
        return;
      }
      final previousHasDuplicateFacts =
          previous.amount != null &&
          previous.currency != null &&
          previous.transactionDate != null &&
          previous.direction != null;
      final currentHasDuplicateFacts =
          row.amount != null &&
          row.currency != null &&
          row.transactionDate != null &&
          row.direction != null;
      final previousKey = previousHasDuplicateFacts
          ? _duplicateKeyForRow(previous)
          : null;
      final currentKey = currentHasDuplicateFacts
          ? _duplicateKeyForRow(row)
          : null;
      if (previousKey == currentKey) return;
      if (previousKey != null) {
        await _repairDuplicateReview(previous, removeStatementReference: true);
      }
      if (currentKey != null && row.status == StatementRowStatus.unresolved) {
        final activeIds = await duplicateGroups.findActiveTransactionIdsForKey(
          currentKey,
        );
        if (activeIds.isNotEmpty) {
          await _repairDuplicateReview(
            row,
            pendingStatementRows: [
              DuplicateCandidateStatementRow(
                statementId: row.statementId,
                rowId: row.id,
              ),
            ],
          );
        }
      }
    }),
  );

  Future<ApplicationResult<List<ReconciliationMatchCandidate>>> likelyMatches(
    StatementRow row,
    String paymentSourceId,
  ) => _runExclusive(
    () => runApplication('cross-check statement row', () async {
      if (row.amount == null ||
          row.currency == null ||
          row.transactionDate == null) {
        return const [];
      }
      final result =
          await FindReceiptPaymentMatch(
            transactions,
            consistencyGate: consistencyGate,
          ).callAll(
            ReceiptPaymentMatchCommand(
              amount: Money(
                amount: DecimalValue.parse(row.amount!),
                currency: CurrencyCode(row.currency!),
              ),
              currency: row.currency!,
              transactionDate: row.transactionDate!.toIso8601String().substring(
                0,
                10,
              ),
              merchant: row.description,
              paymentSourceId: paymentSourceId,
              direction: _directionForRow(row),
            ),
          );
      return switch (result) {
        ApplicationSuccess<List<ReconciliationMatchCandidate>>(:final value) =>
          value,
        ApplicationFailure<List<ReconciliationMatchCandidate>>() => const [],
      };
    }),
  );

  Future<ApplicationResult<void>> link(
    StatementRow row,
    String transactionId,
  ) => _runExclusive(
    () => runApplication('link statement row', () async {
      final statement = await statements.findStatement(row.statementId);
      if (statement == null) {
        throw const RepositoryException(
          RepositoryFailureCode.notFound,
          'link statement row: statement',
        );
      }
      final persisted = (await statements.listRows(
        row.statementId,
      )).where((value) => value.id == row.id).firstOrNull;
      final alreadyLinked =
          persisted?.status == StatementRowStatus.linked &&
          persisted?.transactionId == transactionId;
      if (persisted?.status == StatementRowStatus.linked && !alreadyLinked) {
        throw const DomainValidationException(
          code: DomainErrorCode.invalidState,
          field: 'transactionId',
          message:
              'The statement row is already linked to another transaction.',
        );
      }
      final linked = alreadyLinked
          ? persisted!
          : _copy(
              row,
              status: StatementRowStatus.linked,
              transactionId: transactionId,
              dispositionReason: 'linkExisting',
              updatedAt: clock.now(),
            );
      await _invalidateAnalysis();
      if (!alreadyLinked) await workflow.linkRow(linked);
      await _linkStatementEvidence(statement, transactionId);
      await _repairDuplicateReview(linked);
    }),
  );

  Future<ApplicationResult<TransactionDto>> save(
    StatementRow row,
    String paymentSourceId, {
    bool allowCreateNew = false,
  }) => _runExclusive(
    () => runApplication('save statement row', () async {
      final statement = await statements.findStatement(row.statementId);
      if (statement == null) {
        throw const RepositoryException(
          RepositoryFailureCode.notFound,
          'save statement row: statement',
        );
      }
      if ((row.status == StatementRowStatus.saved ||
              row.status == StatementRowStatus.linked) &&
          row.transactionId != null) {
        final existing = await transactions.findById(
          TransactionId(row.transactionId!),
        );
        if (existing != null) {
          await _invalidateAnalysis();
          await _linkStatementEvidence(statement, existing.id.value);
          await _repairDuplicateReview(
            row,
            resolvedStatus: allowCreateNew
                ? DuplicateCandidateGroupStatus.keepBoth
                : null,
          );
          return TransactionDto.fromDomain(existing);
        }
      }
      final prepared = await _prepareTransaction(
        row,
        paymentSourceId,
        allowCreateNew: allowCreateNew,
      );
      final transaction = prepared.value;
      final now = transaction.updatedAt;
      final transactionId = transaction.id.value;
      final savedRow = _copy(
        row,
        status: StatementRowStatus.saved,
        transactionId: transactionId,
        dispositionReason: 'createNew',
        updatedAt: now,
      );
      await _invalidateAnalysis();
      await workflow.saveRowTransaction(savedRow, transaction);
      await _linkStatementEvidence(statement, transactionId);
      await _repairDuplicateReview(
        savedRow,
        resolvedStatus: allowCreateNew
            ? DuplicateCandidateGroupStatus.keepBoth
            : null,
      );
      final dto = TransactionDto.fromDomain(transaction);
      return TransactionDto(
        id: dto.id,
        amount: dto.amount,
        currency: dto.currency,
        direction: dto.direction,
        status: dto.status,
        reviewState: dto.reviewState,
        createdAt: dto.createdAt,
        updatedAt: dto.updatedAt,
        occurredAt: dto.occurredAt,
        transactionDate: dto.transactionDate,
        timeZoneId: dto.timeZoneId,
        description: dto.description,
        rawCounterparty: dto.rawCounterparty,
        sourceLanguage: dto.sourceLanguage,
        notes: dto.notes,
        externalReference: dto.externalReference,
        paymentSourceId: dto.paymentSourceId,
        merchantId: dto.merchantId,
        categoryId: dto.categoryId,
        subcategoryId: dto.subcategoryId,
        tagIds: dto.tagIds,
        provenance: dto.provenance,
        normalizedMoney: dto.normalizedMoney,
        classificationProposal: prepared.proposal,
      );
    }),
  );

  Future<void> _linkStatementEvidence(
    FinancialStatement statement,
    String transactionId,
  ) async {
    final evidenceRepository = evidence;
    if (evidenceRepository == null) return;
    await evidenceRepository.link(
      AttachmentLink(
        id: AttachmentLinkId(
          'statement-attachment-${statement.id}-$transactionId',
        ),
        transactionId: TransactionId(transactionId),
        evidenceId: EvidenceId(statement.evidenceId),
        createdAt: clock.now(),
      ),
    );
  }

  Future<_PreparedStatementTransaction> _prepareTransaction(
    StatementRow row,
    String paymentSourceId, {
    required bool allowCreateNew,
  }) async {
    if (row.amount == null ||
        row.currency == null ||
        row.transactionDate == null ||
        row.direction == null) {
      throw const DomainValidationException(
        code: DomainErrorCode.invalidState,
        field: 'statementRow',
        message: 'A date, amount, currency, and direction are required.',
      );
    }
    if (!allowCreateNew) {
      final matches = await likelyMatches(row, paymentSourceId);
      if (matches case ApplicationSuccess<List<ReconciliationMatchCandidate>>(
        value: final values,
      ) when values.isNotEmpty) {
        throw const DomainValidationException(
          code: DomainErrorCode.invalidState,
          field: 'statementRow',
          message:
              'A likely existing transaction requires an explicit decision.',
        );
      }
    }
    final now = clock.now();
    final transactionId = _transactionIdForRow(row);
    final proposalResult = classifier == null
        ? null
        : await classifier!.call(
            merchantId: row.merchantId == null
                ? null
                : MerchantId(row.merchantId!),
            description: row.description ?? row.originalText,
            excludeTransactionId: TransactionId(transactionId),
          );
    final proposal =
        proposalResult is ApplicationSuccess<ClassificationProposal>
        ? proposalResult.value
        : null;
    final resolvedMerchantId = row.merchantId ?? proposal?.merchantId?.value;
    final transaction = Transaction(
      id: TransactionId(transactionId),
      timing: const UnknownTransactionTime(
        UnknownTransactionTimeReason.unknown,
      ),
      money: Money(
        amount: DecimalValue.parse(row.amount!),
        currency: CurrencyCode(row.currency!),
      ),
      direction: _directionForRow(row),
      sourceType: TransactionSourceType.import,
      transactionDate: row.transactionDate!.toIso8601String().substring(0, 10),
      description: row.description,
      rawCounterparty: row.originalText,
      paymentSourceId: PaymentSourceId(row.paymentSourceId ?? paymentSourceId),
      merchantId: resolvedMerchantId == null
          ? null
          : MerchantId(resolvedMerchantId),
      categoryId: row.categoryId == null
          ? proposal?.categoryId
          : CategoryId(row.categoryId!),
      subcategoryId: row.subcategoryId == null && row.categoryId == null
          ? proposal?.subcategoryId
          : row.subcategoryId == null
          ? null
          : CategoryId(row.subcategoryId!),
      tagIds: row.tagIds.map(TagId.new).toList(growable: false),
      externalReference: 'statement-row:${row.id}',
      provenance: [
        Provenance(
          id: ProvenanceId('statement-provenance-${row.id}'),
          sourceType: ProvenanceSourceType.import,
          capturedAt: now,
          sourceId: row.statementId,
          originalRepresentation: row.originalText,
        ),
      ],
      reviewIssues: [
        if (intakePolicy.needsConfidenceReview(row.confidence))
          ReviewIssue(
            id: ReviewIssueId('statement-confidence-${row.id}'),
            transactionId: TransactionId(transactionId),
            reason: ReviewIssueReason.uncertain,
            detail: 'We were not confident reading this statement row.',
            createdAt: now,
          )
        else if (row.status == StatementRowStatus.unresolved)
          ReviewIssue(
            id: ReviewIssueId('statement-unresolved-${row.id}'),
            transactionId: TransactionId(transactionId),
            reason: ReviewIssueReason.uncertain,
            detail: row.reviewReason?.trim().isNotEmpty == true
                ? row.reviewReason!
                : 'This statement row still needs review.',
            createdAt: now,
          ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final classified = applyRules == null
        ? transaction
        : await applyRules!(transaction);
    final resolved = await synchronizeMerchantReviewIssueBestEffort(
      classified,
      now,
      merchantRepository: merchants,
    );
    return _PreparedStatementTransaction(value: resolved, proposal: proposal);
  }

  Future<bool> _repairDuplicateReview(
    StatementRow row, {
    Iterable<String>? candidateTransactionIds,
    Iterable<DuplicateCandidateStatementRow> pendingStatementRows = const [],
    DuplicateCandidateGroupStatus? resolvedStatus,
    bool removeStatementReference = false,
  }) async {
    final key = _duplicateKeyForRow(row);
    final id = 'duplicate:${key.canonical}';
    final existing = (await duplicateGroups.list())
        .where((group) => group.id == id)
        .firstOrNull;
    final activeTransactionIds = await duplicateGroups
        .findActiveTransactionIdsForKey(key);
    final transactionIds = <TransactionId>{
      ...?existing?.transactionIds,
      ...activeTransactionIds,
      ...?candidateTransactionIds?.map(TransactionId.new),
    }.toList()..sort((left, right) => left.value.compareTo(right.value));
    final persistedStatementRows = existing?.statementRows ?? const [];
    final statementRowsById = <String, DuplicateCandidateStatementRow>{};
    for (final value in [...persistedStatementRows, ...pendingStatementRows]) {
      if (value.statementId == row.statementId && value.rowId == row.id) {
        final keep =
            !removeStatementReference &&
            (row.status == StatementRowStatus.unresolved ||
                pendingStatementRows.isNotEmpty);
        if (!keep) continue;
      }
      statementRowsById[value.canonical] = value;
    }
    final statementRows = statementRowsById.values.toList(growable: false);
    if (transactionIds.length < 2 && statementRows.isEmpty) {
      if (existing?.isUnresolved ?? false) await duplicateGroups.remove(id);
      return false;
    }
    final membershipUnchanged =
        existing != null &&
        _sameTransactionIds(existing.transactionIds, transactionIds) &&
        _sameStatementRows(existing.statementRows, statementRows);
    final decision = resolvedStatus != null && statementRows.isEmpty
        ? resolvedStatus
        : null;
    final now = clock.now();
    await duplicateGroups.save(
      DuplicateCandidateGroup(
        id: id,
        transactionIds: transactionIds,
        duplicateKey: key,
        status: membershipUnchanged
            ? existing.status
            : decision ?? DuplicateCandidateGroupStatus.unresolved,
        selectedTransactionId: membershipUnchanged
            ? existing.selectedTransactionId
            : null,
        statementRows: statementRows,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    return true;
  }

  Future<List<String>> _candidateTransactionIdsForRow(StatementRow row) async {
    final reference = '${row.statementId}:${row.id}';
    for (final group in await duplicateGroups.list()) {
      if (group.statementRows.any((value) => value.canonical == reference)) {
        return group.transactionIds.map((value) => value.value).toList();
      }
    }
    return const [];
  }

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }

  Future<void> _invalidateAnalysis() async {
    final invalidation = invalidateAnalysis;
    if (invalidation == null) return;
    final result = await invalidation(
      AnalysisInvalidationReason.duplicateDecisionChanged,
      clock.now(),
    );
    if (result is ApplicationFailure<void>) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'invalidate analysis after statement duplicate decision',
      );
    }
  }

  Future<void> _removeStatementDuplicateReferences(String statementId) async {
    for (final group in await duplicateGroups.list()) {
      final remaining = group.statementRows
          .where((row) => row.statementId != statementId)
          .toList(growable: false);
      if (remaining.length == group.statementRows.length) continue;
      if (remaining.isEmpty && group.transactionIds.length < 2) {
        await duplicateGroups.remove(group.id);
        continue;
      }
      await duplicateGroups.save(
        DuplicateCandidateGroup(
          id: group.id,
          transactionIds: group.transactionIds,
          duplicateKey: group.duplicateKey,
          status: group.status,
          selectedTransactionId: group.selectedTransactionId,
          statementRows: remaining,
          integrityIssue: group.integrityIssue,
          createdAt: group.createdAt,
          updatedAt: clock.now(),
        ),
      );
    }
  }

  static bool _sameTransactionIds(
    List<TransactionId> left,
    List<TransactionId> right,
  ) {
    if (left.length != right.length) return false;
    final a = left.map((value) => value.value).toList()..sort();
    final b = right.map((value) => value.value).toList()..sort();
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  static bool _sameStatementRows(
    List<DuplicateCandidateStatementRow> left,
    List<DuplicateCandidateStatementRow> right,
  ) {
    final a = left.map((value) => value.canonical).toList()..sort();
    final b = right.map((value) => value.canonical).toList()..sort();
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  Future<void> _markStatementException(StatementRow row, String reason) =>
      statements.updateRow(
        _copy(
          row,
          status: StatementRowStatus.unresolved,
          reviewReason: reason,
          dispositionReason: 'needsReview',
          updatedAt: clock.now(),
        ),
      );

  static String _transactionIdForRow(StatementRow row) =>
      'statement-${row.statementId}-${row.id}';

  static DuplicateTransactionKey _duplicateKeyForRow(StatementRow row) =>
      DuplicateTransactionKey(
        transactionDate: row.transactionDate!.toIso8601String().substring(
          0,
          10,
        ),
        amount: DecimalValue.parse(row.amount!),
        currency: row.currency!.trim().toUpperCase(),
        direction: _directionForRow(row).name,
      );

  static Set<String> _sameBatchDuplicateRowIds(Iterable<StatementRow> rows) {
    final rowsByDuplicateKey = <String, List<String>>{};
    for (final row in rows) {
      if (row.amount == null ||
          row.currency == null ||
          row.transactionDate == null ||
          row.direction == null) {
        continue;
      }
      final key = _duplicateKeyForRow(row);
      rowsByDuplicateKey.putIfAbsent(key.canonical, () => []).add(row.id);
    }
    return rowsByDuplicateKey.values
        .where((ids) => ids.length > 1)
        .expand((ids) => ids)
        .toSet();
  }

  static StatementRow _copy(
    StatementRow row, {
    required StatementRowStatus status,
    String? transactionId,
    String? reviewReason,
    String? dispositionReason,
    StatementRowStatus? statusBeforeSkip,
    bool clearStatusBeforeSkip = false,
    bool clearTransactionId = false,
    required DateTime updatedAt,
  }) => StatementRow(
    id: row.id,
    statementId: row.statementId,
    position: row.position,
    originalText: row.originalText,
    transactionDate: row.transactionDate,
    postingDate: row.postingDate,
    description: row.description,
    amount: row.amount,
    currency: row.currency,
    direction: row.direction,
    kind: row.kind,
    confidence: row.confidence,
    sourceContext: row.sourceContext,
    status: status,
    transactionId: clearTransactionId
        ? null
        : transactionId ?? row.transactionId,
    merchantId: row.merchantId,
    categoryId: row.categoryId,
    subcategoryId: row.subcategoryId,
    tagIds: row.tagIds,
    paymentSourceId: row.paymentSourceId,
    sourceReferenceId: row.sourceReferenceId,
    reviewReason: reviewReason ?? row.reviewReason,
    dispositionReason: dispositionReason ?? row.dispositionReason,
    statusBeforeSkip: clearStatusBeforeSkip
        ? null
        : statusBeforeSkip ?? row.statusBeforeSkip,
    createdAt: row.createdAt,
    updatedAt: updatedAt,
  );

  static TransactionDirection _directionForRow(StatementRow row) {
    if (row.direction == TransactionDirection.income.name) {
      return TransactionDirection.income;
    }
    if (row.direction == TransactionDirection.refund.name ||
        row.kind == StatementRowKind.refund) {
      return TransactionDirection.refund;
    }
    return TransactionDirection.expense;
  }
}
