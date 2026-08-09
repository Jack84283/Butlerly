import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 9, 12);

  test('constructs the minimum valid offline transaction', () {
    final transaction = buildTransaction(createdAt: createdAt);

    expect(transaction.id, TransactionId('transaction-1'));
    expect(transaction.paymentSourceId, isNull);
    expect(transaction.merchantId, isNull);
    expect(transaction.categoryId, isNull);
    expect(transaction.reviewState, TransactionReviewState.clear);
  });

  test('supports an explicit pending or unknown transaction time', () {
    final transaction = buildTransaction(
      createdAt: createdAt,
      timing: const UnknownTransactionTime(
        UnknownTransactionTimeReason.pending,
      ),
    );

    expect(transaction.timing, isA<UnknownTransactionTime>());
  });

  test('requires provenance for every transaction', () {
    expect(
      () => buildTransaction(createdAt: createdAt, provenance: []),
      throwsA(
        isA<DomainValidationException>().having(
          (error) => error.code,
          'code',
          DomainErrorCode.missingProvenance,
        ),
      ),
    );
  });

  test('derives review state from active review issues', () {
    final transaction = buildTransaction(createdAt: createdAt);
    final issue = ReviewIssue(
      id: ReviewIssueId('issue-1'),
      transactionId: transaction.id,
      reason: ReviewIssueReason.duplicateCandidate,
      createdAt: createdAt,
    );

    final underReview = transaction.addReviewIssue(
      issue,
      createdAt.add(const Duration(minutes: 1)),
    );

    expect(underReview.reviewState, TransactionReviewState.needsReview);
    expect(transaction.reviewState, TransactionReviewState.clear);
  });

  test('does not attach a review issue from another transaction', () {
    final transaction = buildTransaction(createdAt: createdAt);
    final issue = ReviewIssue(
      id: ReviewIssueId('issue-1'),
      transactionId: TransactionId('another-transaction'),
      reason: ReviewIssueReason.conflict,
      createdAt: createdAt,
    );

    expect(
      () => transaction.addReviewIssue(issue, createdAt),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('keeps original money when adding normalized money', () {
    final transaction = buildTransaction(createdAt: createdAt);
    final rate = ExchangeRate(
      id: ExchangeRateId('rate-1'),
      fromCurrency: CurrencyCode('EUR'),
      toCurrency: CurrencyCode('USD'),
      rate: DecimalValue.parse('1.17'),
      effectiveAt: createdAt,
      source: 'European Central Bank',
    );
    final normalized = NormalizedMoney(
      original: transaction.money,
      converted: Money(
        amount: DecimalValue.parse('11.70'),
        currency: CurrencyCode('USD'),
      ),
      exchangeRate: rate,
    );

    final enriched = transaction.addNormalizedMoney(normalized, createdAt);

    expect(enriched.money, transaction.money);
    expect(enriched.money.currency, CurrencyCode('EUR'));
    expect(
      enriched.normalizedMoney.single.converted.currency,
      CurrencyCode('USD'),
    );
  });

  test('archives without deleting canonical values or provenance', () {
    final transaction = buildTransaction(createdAt: createdAt);

    final archived = transaction.archive(
      createdAt.add(const Duration(hours: 1)),
    );

    expect(archived.status, TransactionStatus.archived);
    expect(archived.money, transaction.money);
    expect(archived.provenance, transaction.provenance);
  });
}

Transaction buildTransaction({
  required DateTime createdAt,
  TransactionTiming? timing,
  List<Provenance>? provenance,
}) {
  return Transaction(
    id: TransactionId('transaction-1'),
    timing: timing ?? KnownTransactionTime(createdAt),
    money: Money(
      amount: DecimalValue.parse('10.00'),
      currency: CurrencyCode('EUR'),
    ),
    direction: TransactionDirection.expense,
    sourceType: TransactionSourceType.manual,
    provenance:
        provenance ??
        [
          Provenance(
            id: ProvenanceId('provenance-1'),
            sourceType: ProvenanceSourceType.userEntry,
            capturedAt: createdAt,
          ),
        ],
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
