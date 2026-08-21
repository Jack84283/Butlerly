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
