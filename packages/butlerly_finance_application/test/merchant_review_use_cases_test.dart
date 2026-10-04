import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final at = DateTime.utc(2026, 9, 1);

  test(
    'creates a merchant review issue only for usable unresolved evidence',
    () {
      final transaction = _transaction(rawCounterparty: 'SAFEWAY #123');

      final candidate = synchronizeMerchantReviewIssue(transaction, at);

      expect(
        candidate.reviewIssues.single.reason,
        ReviewIssueReason.merchantNeedsReview,
      );
      expect(merchantEvidenceFor(candidate), 'SAFEWAY #123');
      expect(
        synchronizeMerchantReviewIssue(_transaction(), at).reviewIssues,
        isEmpty,
      );
    },
  );

  test('resolving the merchant assignment closes the active issue', () {
    final candidate = synchronizeMerchantReviewIssue(
      _transaction(rawCounterparty: 'TRADER JOES'),
      at,
    );
    final assigned = candidate.assignMerchant(MerchantId('merchant-1'), at);

    final resolved = synchronizeMerchantReviewIssue(assigned, at);

    expect(resolved.reviewIssues.single.status, ReviewIssueStatus.resolved);
  });

  test('deterministic normalization provides candidate grouping semantics', () {
    expect(
      normalizeMerchantName('SAFEWAY #123'),
      normalizeMerchantName('SAFEWAY #123'),
    );
    expect({
      normalizeMerchantName('SAFEWAY #123'),
      normalizeMerchantName('SAFEWAY #123'),
      normalizeMerchantName('TRADER JOES'),
    }, hasLength(2));
  });
}

Transaction _transaction({String? rawCounterparty}) => Transaction(
  id: TransactionId('transaction-1'),
  timing: KnownTransactionTime(DateTime.utc(2026, 9, 1, 12)),
  money: Money(amount: DecimalValue.parse('12'), currency: CurrencyCode('USD')),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  transactionDate: '2026-09-01',
  rawCounterparty: rawCounterparty,
  provenance: [
    Provenance(
      id: ProvenanceId('provenance-1'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: DateTime.utc(2026, 9, 1),
    ),
  ],
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
);
