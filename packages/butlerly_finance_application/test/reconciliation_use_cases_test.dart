import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
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

Transaction _transaction({
  required String id,
  required TransactionSourceType sourceType,
  required String date,
  required String merchant,
  required ProvenanceSourceType provenanceType,
  required DateTime now,
  TransactionDirection direction = TransactionDirection.expense,
}) => Transaction(
  id: TransactionId(id),
  timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
  money: Money(
    amount: DecimalValue.parse('25.00'),
    currency: CurrencyCode('USD'),
  ),
  direction: direction,
  sourceType: sourceType,
  transactionDate: date,
  rawCounterparty: merchant,
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
