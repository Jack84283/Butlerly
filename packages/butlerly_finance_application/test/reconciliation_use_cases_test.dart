import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('candidate generation ignores archived transaction endpoints', () {
    final now = DateTime.utc(2026, 8, 20);
    final receipt = _transaction(
      id: 'archived-endpoint-receipt',
      sourceType: TransactionSourceType.evidenceCapture,
      direction: TransactionDirection.expense,
      date: '2026-08-20',
      merchant: 'Archived endpoint',
      provenanceType: ProvenanceSourceType.scan,
      now: now,
    );
    final archivedPayment = _transaction(
      id: 'archived-endpoint-payment',
      sourceType: TransactionSourceType.import,
      direction: TransactionDirection.expense,
      date: '2026-08-20',
      merchant: 'Archived endpoint',
      provenanceType: ProvenanceSourceType.import,
      now: now,
    ).archive(now);

    final candidates = const ReconciliationCandidateGenerator().generate([
      receipt,
      archivedPayment,
    ]);

    expect(candidates, isEmpty);
  });

  test('refresh retires candidates whose endpoint was archived', () async {
    final now = DateTime.utc(2026, 8, 20);
    final receipt =
        _transaction(
          id: 'refresh-archived-receipt',
          sourceType: TransactionSourceType.evidenceCapture,
          direction: TransactionDirection.expense,
          date: '2026-08-20',
          merchant: 'Archived endpoint',
          provenanceType: ProvenanceSourceType.scan,
          now: now,
        ).addReviewIssue(
          ReviewIssue(
            id: ReviewIssueId('reconciliation-candidate-refresh-archived'),
            transactionId: TransactionId('refresh-archived-receipt'),
            reason: ReviewIssueReason.uncertain,
            detail: 'Pending reconciliation candidate.',
            createdAt: now,
          ),
          now,
        );
    final archivedPayment = _transaction(
      id: 'refresh-archived-payment',
      sourceType: TransactionSourceType.import,
      direction: TransactionDirection.expense,
      date: '2026-08-20',
      merchant: 'Archived endpoint',
      provenanceType: ProvenanceSourceType.import,
      now: now,
    ).archive(now);
    final transactions = _MutableTransactions([receipt, archivedPayment]);
    final candidates = _MemoryCandidates();
    final candidate = ReconciliationCandidate(
      id: 'candidate-refresh-archived',
      receiptTransactionId: receipt.id,
      paymentTransactionId: archivedPayment.id,
      score: 0.9,
      reasons: const ['same amount'],
      status: ReconciliationCandidateStatus.proposed,
    );
    await candidates.save(candidate);

    final result = await RefreshReconciliationCandidates(
      transactions,
      candidates,
    )();

    expect(result, isA<ApplicationSuccess<List<ReconciliationCandidate>>>());
    expect(
      (await candidates.findById(candidate.id))!.status,
      ReconciliationCandidateStatus.rejected,
    );
    final refreshedReceipt = await transactions.findById(receipt.id);
    expect(
      refreshedReceipt!.reviewIssues.single.status,
      ReviewIssueStatus.resolved,
    );
  });

  test('generates a scored candidate between receipt and payment inputs', () {
    final now = DateTime.utc(2026, 8, 20);
    final receipt = Transaction(
      id: TransactionId('receipt-1'),
      timing: const UnknownTransactionTime(
        UnknownTransactionTimeReason.unknown,
      ),
      money: Money(
        amount: DecimalValue.parse('25.00'),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.evidenceCapture,
      transactionDate: '2026-08-20',
      rawCounterparty: 'Starbucks',
      provenance: [
        Provenance(
          id: ProvenanceId('receipt-prov'),
          sourceType: ProvenanceSourceType.scan,
          capturedAt: now,
          originalRepresentation: 'receipt.jpg',
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final payment = Transaction(
      id: TransactionId('payment-1'),
      timing: const UnknownTransactionTime(
        UnknownTransactionTimeReason.unknown,
      ),
      money: receipt.money,
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.import,
      transactionDate: '2026-08-20',
      rawCounterparty: 'Starbucks',
      externalReference: 'chase-card-1234-bank-id-1',
      provenance: [
        Provenance(
          id: ProvenanceId('payment-prov'),
          sourceType: ProvenanceSourceType.import,
          capturedAt: now,
          sourceId: 'statement.csv',
          originalRepresentation: 'row',
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    final candidates = const ReconciliationCandidateGenerator().generate([
      receipt,
      payment,
    ]);

    expect(candidates, hasLength(1));
    expect(candidates.single.score, closeTo(0.95, 0.0001));
    expect(
      candidates.single.confirm().status,
      ReconciliationCandidateStatus.confirmed,
    );
    expect(
      candidates.single.undo().status,
      ReconciliationCandidateStatus.undone,
    );
  });

  test('normalizes merchant punctuation and allows one-day posting drift', () {
    final now = DateTime.utc(2026, 8, 20);
    final receipt = _transaction(
      id: 'receipt-2',
      sourceType: TransactionSourceType.evidenceCapture,
      date: '2026-08-20',
      merchant: 'Starbucks #123',
      provenanceType: ProvenanceSourceType.scan,
      now: now,
    );
    final payment = _transaction(
      id: 'payment-2',
      sourceType: TransactionSourceType.import,
      date: '2026-08-21',
      merchant: 'STARBUCKS-123 POS',
      provenanceType: ProvenanceSourceType.import,
      now: now,
    );

    final candidates = const ReconciliationCandidateGenerator().generate([
      receipt,
      payment,
    ]);

    expect(candidates, hasLength(1));
    expect(candidates.single.reasons, contains('merchant text matches'));
    expect(
      candidates.single.reasons,
      contains('transaction date is within one day'),
    );
  });

  test('does not generate a candidate for conflicting directions', () {
    final now = DateTime.utc(2026, 8, 20);
    final receipt = _transaction(
      id: 'receipt-3',
      sourceType: TransactionSourceType.evidenceCapture,
      date: '2026-08-20',
      merchant: 'Cafe',
      provenanceType: ProvenanceSourceType.scan,
      now: now,
    );
    final refund = _transaction(
      id: 'payment-3',
      sourceType: TransactionSourceType.import,
      date: '2026-08-20',
      merchant: 'Cafe',
      provenanceType: ProvenanceSourceType.import,
      direction: TransactionDirection.refund,
      now: now,
    );

    expect(
      const ReconciliationCandidateGenerator().generate([receipt, refund]),
      isEmpty,
    );
  });

  test(
    'matcher preserves compatible tip differences as explainable conflicts',
    () {
      final now = DateTime.utc(2026, 8, 20);
      final receipt = _transaction(
        id: 'receipt-tip',
        sourceType: TransactionSourceType.evidenceCapture,
        date: '2026-08-20',
        merchant: 'Cafe',
        provenanceType: ProvenanceSourceType.scan,
        now: now,
      );
      final settled = Transaction(
        id: TransactionId('settled-tip'),
        timing: const UnknownTransactionTime(
          UnknownTransactionTimeReason.unknown,
        ),
        money: Money(
          amount: DecimalValue.parse('27.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.import,
        transactionDate: '2026-08-20',
        rawCounterparty: 'Cafe',
        provenance: [
          Provenance(
            id: ProvenanceId('settled-tip-prov'),
            sourceType: ProvenanceSourceType.import,
            capturedAt: now,
            originalRepresentation: 'Cafe',
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final assessment = ReconciliationMatcher.assess(receipt, settled);
      expect(assessment.incompatible, isFalse);
      expect(
        assessment.reasons,
        contains('amount is within 10% (possible tip or adjustment)'),
      );
      expect(assessment.conflicts, contains('amount differs'));
    },
  );

  test(
    'callAll preserves multiple plausible candidates instead of hiding ambiguity',
    () async {
      final now = DateTime.utc(2026, 8, 20);
      final repository = _FakeTransactions([
        _transaction(
          id: 'manual-a',
          sourceType: TransactionSourceType.manual,
          date: '2026-08-20',
          merchant: 'Cafe',
          provenanceType: ProvenanceSourceType.userEntry,
          now: now,
        ),
        _transaction(
          id: 'manual-b',
          sourceType: TransactionSourceType.manual,
          date: '2026-08-20',
          merchant: 'Cafe',
          provenanceType: ProvenanceSourceType.userEntry,
          now: now,
        ),
      ]);
      final result = await FindReceiptPaymentMatch(repository).callAll(
        ReceiptPaymentMatchCommand(
          amount: Money(
            amount: DecimalValue.parse('25.00'),
            currency: CurrencyCode('USD'),
          ),
          currency: 'USD',
          transactionDate: '2026-08-20',
          merchant: 'Cafe',
        ),
      );
      expect(
        result,
        isA<ApplicationSuccess<List<ReconciliationMatchCandidate>>>(),
      );
      expect(
        (result as ApplicationSuccess<List<ReconciliationMatchCandidate>>)
            .value,
        hasLength(2),
      );
    },
  );

  test(
    'receipt reconciliation can target a statement-created transaction',
    () async {
      final now = DateTime.utc(2026, 8, 20);
      final repository = _FakeTransactions([
        _transaction(
          id: 'statement-created',
          sourceType: TransactionSourceType.import,
          date: '2026-08-20',
          merchant: 'Cafe',
          provenanceType: ProvenanceSourceType.import,
          now: now,
        ),
        _transaction(
          id: 'receipt-created',
          sourceType: TransactionSourceType.evidenceCapture,
          date: '2026-08-20',
          merchant: 'Cafe',
          provenanceType: ProvenanceSourceType.scan,
          now: now,
        ),
      ]);
      final result = await FindReceiptPaymentMatch(repository).callAll(
        ReceiptPaymentMatchCommand(
          amount: Money(
            amount: DecimalValue.parse('25.00'),
            currency: CurrencyCode('USD'),
          ),
          currency: 'USD',
          transactionDate: '2026-08-20',
          merchant: 'Cafe',
        ),
      );
      final values =
          (result as ApplicationSuccess<List<ReconciliationMatchCandidate>>)
              .value;
      expect(values, hasLength(1));
      expect(values.single.transaction.id, 'statement-created');
    },
  );

  test(
    'confirm delegates candidate and link as one workflow operation',
    () async {
      final workflow = _FakeWorkflow();
      final candidate = ReconciliationCandidate(
        id: 'candidate-atomic',
        receiptTransactionId: TransactionId('receipt-atomic'),
        paymentTransactionId: TransactionId('payment-atomic'),
        score: .95,
        reasons: const ['exact match'],
      );

      final result = await ConfirmReconciliation(workflow).call(candidate);

      expect(result, isA<ApplicationSuccess<void>>());
      expect(workflow.confirmedCandidate?.id, candidate.id);
      expect(workflow.confirmedLink?.candidateId, candidate.id);
      expect(
        workflow.confirmedLink?.receiptTransactionId,
        candidate.receiptTransactionId,
      );
      expect(workflow.rejected, isFalse);
    },
  );

  test(
    'confirm rejects persisted candidates with invalid endpoint roles',
    () async {
      final workflow = _FakeWorkflow();
      final receipt = _transaction(
        id: 'invalid-role-receipt',
        sourceType: TransactionSourceType.manual,
        date: '2026-08-20',
        merchant: 'Cafe',
        provenanceType: ProvenanceSourceType.userEntry,
        now: DateTime.utc(2026, 8, 20),
      );
      final payment = _transaction(
        id: 'valid-role-payment',
        sourceType: TransactionSourceType.import,
        date: '2026-08-20',
        merchant: 'Cafe',
        provenanceType: ProvenanceSourceType.import,
        now: DateTime.utc(2026, 8, 20),
      );
      final result =
          await ConfirmReconciliation(
            workflow,
            transactions: _MutableTransactions([receipt, payment]),
          ).call(
            ReconciliationCandidate(
              id: 'invalid-role-candidate',
              receiptTransactionId: receipt.id,
              paymentTransactionId: payment.id,
              score: .95,
              reasons: const ['exact match'],
            ),
          );

      expect(result, isA<ApplicationFailure<void>>());
      expect(workflow.confirmedCandidate, isNull);
    },
  );

  test('confirm invalidates materialized financial analysis', () async {
    final workflow = _FakeWorkflow();
    final results = _InvalidationResults();
    final candidate = ReconciliationCandidate(
      id: 'candidate-invalidates-analysis',
      receiptTransactionId: TransactionId('receipt-invalidates-analysis'),
      paymentTransactionId: TransactionId('payment-invalidates-analysis'),
      score: .95,
      reasons: const ['exact match'],
    );

    final result = await ConfirmReconciliation(
      workflow,
      transactions: null,
      invalidateAnalysis: InvalidateAnalysis(
        _InvalidationFindings(),
        results: results,
      ),
    ).call(candidate);

    expect(result, isA<ApplicationSuccess<void>>());
    expect(results.markStaleCalls, 1);
  });

  test('confirmation does not commit when invalidation fails', () async {
    final workflow = _FakeWorkflow();
    final candidate = ReconciliationCandidate(
      id: 'candidate-invalidation-failure',
      receiptTransactionId: TransactionId('receipt-invalidation-failure'),
      paymentTransactionId: TransactionId('payment-invalidation-failure'),
      score: .95,
      reasons: const ['exact match'],
    );

    final result = await ConfirmReconciliation(
      workflow,
      invalidateAnalysis: InvalidateAnalysis(
        _InvalidationFindings(),
        results: _ThrowingInvalidationResults(),
      ),
    ).call(candidate);

    expect(result, isA<ApplicationFailure<void>>());
    expect(workflow.confirmedCandidate, isNull);
  });

  test('saving a reconciliation candidate invalidates analysis', () async {
    final candidates = _MemoryReconciliationCandidates();
    final results = _InvalidationResults();
    final candidate = ReconciliationCandidate(
      id: 'candidate-save-invalidates',
      receiptTransactionId: TransactionId('receipt-save-invalidates'),
      paymentTransactionId: TransactionId('payment-save-invalidates'),
      score: .9,
      reasons: const ['near match'],
    );

    final result = await SaveReconciliationCandidate(
      candidates,
      invalidateAnalysis: InvalidateAnalysis(
        _InvalidationFindings(),
        results: results,
      ),
    )(candidate);

    expect(result, isA<ApplicationSuccess<void>>());
    expect(results.markStaleCalls, 1);
    expect((await candidates.listAll()).single.id, candidate.id);
  });

  test(
    'confirmation failure after invalidation leaves the workflow unchanged',
    () async {
      final workflow = _FailingWorkflow();
      final results = _InvalidationResults();
      final candidate = ReconciliationCandidate(
        id: 'candidate-mutation-failure',
        receiptTransactionId: TransactionId('receipt-mutation-failure'),
        paymentTransactionId: TransactionId('payment-mutation-failure'),
        score: .95,
        reasons: const ['exact match'],
      );

      final result = await ConfirmReconciliation(
        workflow,
        invalidateAnalysis: InvalidateAnalysis(
          _InvalidationFindings(),
          results: results,
        ),
      ).call(candidate);

      expect(result, isA<ApplicationFailure<void>>());
      expect(workflow.confirmCalls, 1);
      expect(results.markStaleCalls, 1);
    },
  );

  test('matcher preserves material conflicts for review', () {
    final now = DateTime.utc(2026, 8, 20);
    final receipt = _transaction(
      id: 'receipt-conflict',
      sourceType: TransactionSourceType.evidenceCapture,
      date: '2026-08-20',
      merchant: 'Cafe',
      provenanceType: ProvenanceSourceType.scan,
      now: now,
      paymentSourceId: 'cash',
    );
    final payment = _transaction(
      id: 'payment-conflict',
      sourceType: TransactionSourceType.manual,
      date: '2026-09-20',
      merchant: 'Market',
      provenanceType: ProvenanceSourceType.userEntry,
      now: now,
      paymentSourceId: 'card',
      currency: 'EUR',
    );
    final assessment = ReconciliationMatcher.assess(receipt, payment);
    expect(
      assessment.conflicts,
      containsAll([
        'currency conflicts',
        'transaction date differs',
        'merchant text differs',
        'payment source differs',
      ]),
    );
  });

  test('reject delegates only rejection and never creates a link', () async {
    final workflow = _FakeWorkflow();
    final candidate = ReconciliationCandidate(
      id: 'candidate-reject',
      receiptTransactionId: TransactionId('receipt-reject'),
      paymentTransactionId: TransactionId('payment-reject'),
      score: .80,
      reasons: const ['near match'],
    );

    final result = await RejectReconciliation(workflow).call(candidate);

    expect(result, isA<ApplicationSuccess<void>>());
    expect(workflow.rejected, isTrue);
    expect(workflow.confirmedLink, isNull);
  });

  test('reject invalidates analysis without an active review issue', () async {
    final workflow = _FakeWorkflow();
    final results = _InvalidationResults();
    final candidate = ReconciliationCandidate(
      id: 'candidate-reject-invalidates',
      receiptTransactionId: TransactionId('receipt-reject-invalidates'),
      paymentTransactionId: TransactionId('payment-reject-invalidates'),
      score: .80,
      reasons: const ['near match'],
    );

    final result = await RejectReconciliation(
      workflow,
      invalidateAnalysis: InvalidateAnalysis(
        _InvalidationFindings(),
        results: results,
      ),
    ).call(candidate);

    expect(result, isA<ApplicationSuccess<void>>());
    expect(results.markStaleCalls, 1);
  });

  test(
    'save link requires a confirmed matching candidate and rejects conflicts',
    () async {
      final candidates = _MemoryReconciliationCandidates();
      final links = _MemoryReconciliationLinks();
      final candidate = ReconciliationCandidate(
        id: 'candidate-link-validation',
        receiptTransactionId: TransactionId('receipt-link-validation'),
        paymentTransactionId: TransactionId('payment-link-validation'),
        score: .95,
        reasons: const ['exact match'],
        status: ReconciliationCandidateStatus.confirmed,
      );
      await candidates.save(candidate);
      final valid = ReconciliationLink(
        id: 'link-validation',
        candidateId: candidate.id,
        receiptTransactionId: candidate.receiptTransactionId,
        paymentTransactionId: candidate.paymentTransactionId,
        createdAt: DateTime.utc(2026, 8, 20),
      );

      final save = SaveReconciliationLink(links, candidates: candidates);
      expect(await save(valid), isA<ApplicationSuccess<void>>());
      expect(await save(valid), isA<ApplicationSuccess<void>>());

      final conflicting = ReconciliationLink(
        id: 'conflicting-link',
        candidateId: candidate.id,
        receiptTransactionId: candidate.receiptTransactionId,
        paymentTransactionId: candidate.paymentTransactionId,
        createdAt: valid.createdAt,
      );
      expect(await save(conflicting), isA<ApplicationFailure<void>>());

      final proposed = ReconciliationCandidate(
        id: 'candidate-proposed-link',
        receiptTransactionId: candidate.receiptTransactionId,
        paymentTransactionId: candidate.paymentTransactionId,
        score: candidate.score,
        reasons: candidate.reasons,
        status: ReconciliationCandidateStatus.proposed,
      );
      await candidates.save(proposed);
      expect(
        await save(
          ReconciliationLink(
            id: 'link-proposed',
            candidateId: proposed.id,
            receiptTransactionId: proposed.receiptTransactionId,
            paymentTransactionId: proposed.paymentTransactionId,
            createdAt: valid.createdAt,
          ),
        ),
        isA<ApplicationFailure<void>>(),
      );

      final overlapping = ReconciliationCandidate(
        id: 'candidate-overlapping-link',
        receiptTransactionId: candidate.receiptTransactionId,
        paymentTransactionId: TransactionId('payment-link-validation-2'),
        score: candidate.score,
        reasons: candidate.reasons,
        status: ReconciliationCandidateStatus.confirmed,
      );
      await candidates.save(overlapping);
      expect(
        await save(
          ReconciliationLink(
            id: 'link-overlapping',
            candidateId: overlapping.id,
            receiptTransactionId: overlapping.receiptTransactionId,
            paymentTransactionId: overlapping.paymentTransactionId,
            createdAt: valid.createdAt,
          ),
        ),
        isA<ApplicationFailure<void>>(),
      );
    },
  );

  test(
    'refresh creates one issue and never reopens a decided candidate',
    () async {
      final now = DateTime.utc(2026, 8, 20);
      final receipt = _transaction(
        id: 'receipt-lifecycle',
        sourceType: TransactionSourceType.evidenceCapture,
        date: '2026-08-20',
        merchant: 'Cafe',
        provenanceType: ProvenanceSourceType.scan,
        now: now,
      );
      final payment = _transaction(
        id: 'payment-lifecycle',
        sourceType: TransactionSourceType.import,
        date: '2026-08-20',
        merchant: 'Cafe',
        provenanceType: ProvenanceSourceType.import,
        now: now,
      );
      final transactions = _MutableTransactions([receipt, payment]);
      final candidates = _MemoryCandidates();
      final refresh = RefreshReconciliationCandidates(transactions, candidates);

      await refresh();
      await refresh();
      final candidate = (await candidates.listAll()).single;
      expect(
        transactions.values.singleWhere((v) => v.id == receipt.id).reviewIssues,
        hasLength(1),
      );

      await ConfirmReconciliation(_FakeWorkflow(), transactions: transactions)(
        candidate,
      );
      expect(
        transactions.values
            .singleWhere((v) => v.id == receipt.id)
            .reviewIssues
            .single
            .status,
        ReviewIssueStatus.resolved,
      );
      await refresh();
      expect(
        transactions.values
            .singleWhere((v) => v.id == receipt.id)
            .reviewIssues
            .single
            .status,
        ReviewIssueStatus.resolved,
      );
    },
  );

  test('refreshing reconciliation candidates invalidates analysis', () async {
    final now = DateTime.utc(2026, 8, 20);
    final transactions = _MutableTransactions([
      _transaction(
        id: 'receipt-refresh-invalidates',
        sourceType: TransactionSourceType.evidenceCapture,
        date: '2026-08-20',
        merchant: 'Cafe',
        provenanceType: ProvenanceSourceType.scan,
        now: now,
      ),
      _transaction(
        id: 'payment-refresh-invalidates',
        sourceType: TransactionSourceType.import,
        date: '2026-08-20',
        merchant: 'Cafe',
        provenanceType: ProvenanceSourceType.import,
        now: now,
      ),
    ]);
    final candidates = _MemoryCandidates();
    final results = _InvalidationResults();

    final result = await RefreshReconciliationCandidates(
      transactions,
      candidates,
      invalidateAnalysis: InvalidateAnalysis(
        _InvalidationFindings(),
        results: results,
      ),
    )();

    expect(result, isA<ApplicationSuccess<List<ReconciliationCandidate>>>());
    expect(results.markStaleCalls, 1);
  });
}

final class _FakeWorkflow implements ReconciliationWorkflowRepository {
  ReconciliationCandidate? confirmedCandidate;
  ReconciliationLink? confirmedLink;
  bool rejected = false;

  @override
  Future<void> confirm(
    ReconciliationCandidate candidate,
    ReconciliationLink link,
  ) async {
    confirmedCandidate = candidate;
    confirmedLink = link;
  }

  @override
  Future<void> reject(ReconciliationCandidate candidate) async {
    rejected = true;
  }
}

final class _FailingWorkflow implements ReconciliationWorkflowRepository {
  var confirmCalls = 0;

  @override
  Future<void> confirm(
    ReconciliationCandidate candidate,
    ReconciliationLink link,
  ) async {
    confirmCalls++;
    throw const RepositoryException(
      RepositoryFailureCode.unavailable,
      'workflow mutation failed',
    );
  }

  @override
  Future<void> reject(ReconciliationCandidate candidate) async {}
}

final class _FakeTransactions implements TransactionRepository {
  _FakeTransactions(this.values);
  final List<Transaction> values;
  @override
  Future<void> save(Transaction transaction) async {}
  @override
  Future<Transaction?> findById(TransactionId id) async =>
      values.where((v) => v.id == id).firstOrNull;
  @override
  Future<List<Transaction>> listAll() async => values;
  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values;
  @override
  Future<void> removePermanently(TransactionId id) async {}
}

final class _MutableTransactions implements TransactionRepository {
  _MutableTransactions(this.values);
  final List<Transaction> values;
  @override
  Future<void> save(Transaction transaction) async {
    final index = values.indexWhere((v) => v.id == transaction.id);
    if (index >= 0) values[index] = transaction;
  }

  @override
  Future<Transaction?> findById(TransactionId id) async =>
      values.where((v) => v.id == id).firstOrNull;
  @override
  Future<List<Transaction>> listAll() async => values;
  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values;
  @override
  Future<void> removePermanently(TransactionId id) async {}
}

final class _MemoryCandidates implements ReconciliationCandidateRepository {
  final values = <String, ReconciliationCandidate>{};
  @override
  Future<void> save(ReconciliationCandidate candidate) async =>
      values[candidate.id] = candidate;
  @override
  Future<ReconciliationCandidate?> findById(String id) async => values[id];
  @override
  Future<List<ReconciliationCandidate>> listAll() async =>
      values.values.toList();
}

final class _MemoryReconciliationCandidates
    implements ReconciliationCandidateRepository {
  final values = <String, ReconciliationCandidate>{};

  @override
  Future<void> save(ReconciliationCandidate candidate) async =>
      values[candidate.id] = candidate;

  @override
  Future<ReconciliationCandidate?> findById(String id) async => values[id];

  @override
  Future<List<ReconciliationCandidate>> listAll() async =>
      values.values.toList();
}

final class _MemoryReconciliationLinks implements ReconciliationLinkRepository {
  final values = <String, ReconciliationLink>{};

  @override
  Future<void> save(ReconciliationLink link) async => values[link.id] = link;

  @override
  Future<List<ReconciliationLink>> listAll() async => values.values.toList();
}

final class _InvalidationResults implements AnalysisRuleResultRepository {
  var markStaleCalls = 0;

  @override
  Future<List<AnalysisRuleResult>> findAll({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    int? sourceRevision,
  }) async => const [];

  @override
  Future<AnalysisRuleResult?> find({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    String? dimension,
    int? sourceRevision,
  }) async => null;

  @override
  Future<void> save(AnalysisRuleResult result) async {}

  @override
  Future<void> markStale({
    String? periodStart,
    String? periodEnd,
    Set<String>? ruleIds,
  }) async {
    markStaleCalls++;
  }
}

final class _ThrowingInvalidationResults
    implements AnalysisRuleResultRepository {
  @override
  Future<List<AnalysisRuleResult>> findAll({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    int? sourceRevision,
  }) async => const [];

  @override
  Future<AnalysisRuleResult?> find({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    String? dimension,
    int? sourceRevision,
  }) async => null;

  @override
  Future<void> save(AnalysisRuleResult result) async {}

  @override
  Future<void> markStale({
    String? periodStart,
    String? periodEnd,
    Set<String>? ruleIds,
  }) async => throw const RepositoryException(
    RepositoryFailureCode.unavailable,
    'invalidation failed',
  );
}

final class _InvalidationFindings implements AnalysisFindingRepository {
  @override
  Future<void> save(AnalysisFinding finding) async {}

  @override
  Future<List<AnalysisFinding>> list({FindingLifecycle? lifecycle}) async =>
      const [];

  @override
  Future<void> updateLifecycle(
    String id,
    FindingLifecycle lifecycle,
    DateTime at,
  ) async {}
}

Transaction _transaction({
  required String id,
  required TransactionSourceType sourceType,
  required String date,
  required String merchant,
  required ProvenanceSourceType provenanceType,
  required DateTime now,
  TransactionDirection direction = TransactionDirection.expense,
  String paymentSourceId = 'cash',
  String currency = 'USD',
}) => Transaction(
  id: TransactionId(id),
  timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
  money: Money(
    amount: DecimalValue.parse('25.00'),
    currency: CurrencyCode(currency),
  ),
  direction: direction,
  sourceType: sourceType,
  transactionDate: date,
  rawCounterparty: merchant,
  paymentSourceId: PaymentSourceId(paymentSourceId),
  provenance: [
    Provenance(
      id: ProvenanceId('$id-prov'),
      sourceType: provenanceType,
      capturedAt: now,
      originalRepresentation: merchant,
    ),
  ],
  createdAt: now,
  updatedAt: now,
);
