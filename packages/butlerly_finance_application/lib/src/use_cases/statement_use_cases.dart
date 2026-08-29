import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../dto/transaction_dto.dart';
import '../result/application_result.dart';
import 'transaction_use_cases.dart';
import 'reconciliation_use_cases.dart';
import 'duplicate_transaction_use_cases.dart';

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

final class StatementImportAssessment {
  const StatementImportAssessment({
    required this.candidateCount,
    required this.aggregateAmount,
    required this.currency,
    required this.lowConfidenceCount,
    required this.possibleDuplicateCount,
    required this.invalidCount,
  });
  final int candidateCount;
  final String? aggregateAmount;
  final String? currency;
  final int lowConfidenceCount;
  final int possibleDuplicateCount;
  final int invalidCount;
}

final class StatementServices {
  const StatementServices(
    this.statements,
    this.transactions,
    this.workflow,
    this.clock, {
    this.evidence,
    required this.duplicateGroups,
    required this.duplicateChecker,
  });
  final StatementRepository statements;
  final TransactionRepository transactions;
  final StatementWorkflowRepository workflow;
  final ApplicationClock clock;
  final EvidenceRepository? evidence;
  final DuplicateCandidateGroupRepository duplicateGroups;
  final DuplicateTransactionChecker duplicateChecker;

  Future<ApplicationResult<StatementImportAssessment>> assessBatch(
    FinancialStatement statement,
    List<StatementRow> rows,
    String paymentSourceId,
  ) => runApplication('assess statement batch', () async {
    if (statement.paymentSourceId != null &&
        statement.paymentSourceId != paymentSourceId) {
      throw const DomainValidationException(
        code: DomainErrorCode.invalidState,
        field: 'paymentSourceId',
        message: 'The selected payment source does not match the statement.',
      );
    }
    var duplicates = 0;
    for (final row in rows) {
      if (row.amount == null ||
          row.currency == null ||
          row.transactionDate == null ||
          row.direction == null) {
        continue;
      }
      final result = await this.duplicates(row);
      if (result case ApplicationSuccess<DuplicateTransactionCheckResult>(
        value: final value,
      ) when value.candidates.isNotEmpty) {
        duplicates++;
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
      var coefficient = BigInt.zero;
      var scale = 0;
      for (final row in valid) {
        final amount = DecimalValue.parse(row.amount!);
        final targetScale = scale > amount.scale ? scale : amount.scale;
        coefficient =
            coefficient * BigInt.from(10).pow(targetScale - scale) +
            amount.coefficient *
                BigInt.from(10).pow(targetScale - amount.scale);
        scale = targetScale;
      }
      aggregate = DecimalValue.fromParts(
        coefficient: coefficient,
        scale: scale,
      ).toString();
    }
    return StatementImportAssessment(
      candidateCount: rows.length,
      aggregateAmount: aggregate,
      currency: currency,
      lowConfidenceCount: rows
          .where((row) => (row.confidence ?? 1) <= .5)
          .length,
      possibleDuplicateCount: duplicates,
      invalidCount: rows.length - valid.length,
    );
  });

  Future<ApplicationResult<StatementImportSummary>> importBatch(
    FinancialStatement statement,
    List<StatementRow> rows,
    String paymentSourceId,
  ) => runApplication('import statement batch', () async {
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
    for (final row in rows) {
      if (row.amount == null ||
          row.currency == null ||
          row.transactionDate == null ||
          row.direction == null) {
        failed++;
        continue;
      }
      final duplicate = await duplicates(row);
      final result = await save(row, paymentSourceId, allowCreateNew: true);
      if (result is! ApplicationSuccess<TransactionDto>) {
        failed++;
        continue;
      }
      imported++;
      if ((row.confidence ?? 1) <= .5) needsReview++;
      final candidates =
          duplicate is ApplicationSuccess<DuplicateTransactionCheckResult>
          ? duplicate.value.candidates
          : const <DuplicateTransactionCandidate>[];
      if (candidates.isNotEmpty) {
        possibleDuplicates++;
        final transactionIds = [
          result.value.id,
          ...candidates.map((candidate) => candidate.transaction.id),
        ].map(TransactionId.new).toList();
        final key = DuplicateTransactionKey(
          transactionDate: row.transactionDate!.toIso8601String().substring(
            0,
            10,
          ),
          amount: DecimalValue.parse(row.amount!),
          currency: row.currency!,
          direction: _directionForRow(row).name,
        );
        final now = clock.now();
        await duplicateGroups.save(
          DuplicateCandidateGroup(
            id: 'statement-duplicate-${row.id}',
            transactionIds: transactionIds,
            duplicateKey: key,
            status: DuplicateCandidateGroupStatus.unresolved,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }
    return StatementImportSummary(
      imported: imported,
      needsReview: needsReview,
      possibleDuplicates: possibleDuplicates,
      failed: failed,
    );
  });

  Future<ApplicationResult<StatementImportSummary>> importRows(
    FinancialStatement statement,
    List<StatementRow> rows,
    String paymentSourceId,
  ) => importBatch(statement, rows, paymentSourceId);

  Future<ApplicationResult<DuplicateTransactionCheckResult>> duplicates(
    StatementRow row,
  ) async {
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
      ),
    );
  }

  Future<ApplicationResult<void>> create(
    FinancialStatement statement,
    List<StatementRow> rows,
  ) => runApplication('create statement', () async {
    await statements.saveStatement(statement);
    if (rows.isNotEmpty) await statements.saveRows(rows);
  });

  Future<ApplicationResult<List<FinancialStatement>>> list() =>
      runApplication('list statements', () => statements.listStatements());

  Future<ApplicationResult<List<StatementRow>>> rows(String id) =>
      runApplication('list statement rows', () => statements.listRows(id));

  Future<ApplicationResult<void>> addRows(List<StatementRow> rows) =>
      runApplication('add statement rows', () => statements.saveRows(rows));

  Future<ApplicationResult<void>> assignSource(String id, String sourceId) =>
      runApplication(
        'assign statement payment source',
        () => statements.assignPaymentSource(id, sourceId, clock.now()),
      );

  Future<ApplicationResult<void>> setDisposition(
    StatementRow row,
    StatementRowStatus status,
  ) => runApplication(
    'update statement row',
    () => statements.updateRow(
      _copy(row, status: status, updatedAt: clock.now()),
    ),
  );

  Future<ApplicationResult<void>> correct(StatementRow row) =>
      runApplication('correct statement row', () => statements.updateRow(row));

  Future<ApplicationResult<List<ReconciliationMatchCandidate>>> likelyMatches(
    StatementRow row,
    String paymentSourceId,
  ) => runApplication('cross-check statement row', () async {
    if (row.amount == null ||
        row.currency == null ||
        row.transactionDate == null) {
      return const [];
    }
    final result = await FindReceiptPaymentMatch(transactions).callAll(
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
  });

  Future<ApplicationResult<void>> link(
    StatementRow row,
    String transactionId,
  ) => runApplication('link statement row', () async {
    final statement = await statements.findStatement(row.statementId);
    if (statement == null) {
      throw const RepositoryException(
        RepositoryFailureCode.notFound,
        'link statement row: statement',
      );
    }
    await workflow.linkRow(
      _copy(
        row,
        status: StatementRowStatus.linked,
        transactionId: transactionId,
        dispositionReason: 'linkExisting',
        updatedAt: clock.now(),
      ),
    );
    final evidenceRepository = evidence;
    if (evidenceRepository != null) {
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
  });

  Future<ApplicationResult<TransactionDto>> save(
    StatementRow row,
    String paymentSourceId, {
    bool allowCreateNew = false,
  }) => runApplication('save statement row', () async {
    if ((row.status == StatementRowStatus.saved ||
            row.status == StatementRowStatus.linked) &&
        row.transactionId != null) {
      final existing = await transactions.findById(
        TransactionId(row.transactionId!),
      );
      if (existing != null) return TransactionDto.fromDomain(existing);
    }
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
    final transactionId = 'statement-${row.statementId}-${row.id}';
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
      merchantId: row.merchantId == null ? null : MerchantId(row.merchantId!),
      categoryId: row.categoryId == null ? null : CategoryId(row.categoryId!),
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
      reviewIssues: row.confidence != null && row.confidence! <= .5
          ? [
              ReviewIssue(
                id: ReviewIssueId('statement-confidence-${row.id}'),
                transactionId: TransactionId(transactionId),
                reason: ReviewIssueReason.uncertain,
                detail: 'We were not confident reading this statement row.',
                createdAt: now,
              ),
            ]
          : const [],
      createdAt: now,
      updatedAt: now,
    );
    await workflow.saveRowTransaction(
      _copy(
        row,
        status: StatementRowStatus.saved,
        transactionId: transactionId,
        dispositionReason: 'createNew',
        updatedAt: now,
      ),
      transaction,
    );
    return TransactionDto.fromDomain(transaction);
  });

  static StatementRow _copy(
    StatementRow row, {
    required StatementRowStatus status,
    String? transactionId,
    String? dispositionReason,
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
    transactionId: transactionId ?? row.transactionId,
    merchantId: row.merchantId,
    categoryId: row.categoryId,
    tagIds: row.tagIds,
    paymentSourceId: row.paymentSourceId,
    sourceReferenceId: row.sourceReferenceId,
    reviewReason: row.reviewReason,
    dispositionReason: dispositionReason ?? row.dispositionReason,
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
