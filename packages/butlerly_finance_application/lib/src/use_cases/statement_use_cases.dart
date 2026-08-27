import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../dto/transaction_dto.dart';
import '../result/application_result.dart';
import 'transaction_use_cases.dart';
import 'reconciliation_use_cases.dart';

final class StatementServices {
  const StatementServices(
    this.statements,
    this.transactions,
    this.workflow,
    this.clock,
  );
  final StatementRepository statements;
  final TransactionRepository transactions;
  final StatementWorkflowRepository workflow;
  final ApplicationClock clock;

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
  ) => runApplication(
    'link statement row',
    () => workflow.linkRow(
      _copy(
        row,
        status: StatementRowStatus.linked,
        transactionId: transactionId,
        dispositionReason: 'linkExisting',
        updatedAt: clock.now(),
      ),
    ),
  );

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
