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
}
