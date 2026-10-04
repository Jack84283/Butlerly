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

  test('synchronization preserves a dismissed merchant review issue', () {
    final candidate = synchronizeMerchantReviewIssue(
      _transaction(rawCounterparty: 'TRADER JOES'),
      at,
    );
    final dismissed = candidate.dismissReviewIssue(
      candidate.reviewIssues.single.id,
      at,
    );

    final synchronized = synchronizeMerchantReviewIssue(dismissed, at);

    expect(
      synchronized.reviewIssues.single.status,
      ReviewIssueStatus.dismissed,
    );
  });

  test('uses parsed description before noisy raw statement evidence', () {
    final merchant = Merchant(
      id: MerchantId('merchant-trader-joes'),
      name: 'Trader Joes',
      defaultCategoryId: CategoryId('category.food'),
    );
    final transaction = _transaction(
      rawCounterparty: 'BANK PREFIX TRADER JOES #123',
      description: 'Trader Joes',
    );

    expect(
      synchronizeMerchantReviewIssue(
        transaction,
        at,
        merchants: [merchant],
      ).reviewIssues,
      isEmpty,
    );
    expect(merchantEvidenceFor(transaction), 'Trader Joes');
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

  test(
    'canonical, alias, and normalization-pattern matches resolve evidence',
    () {
      final merchantId = MerchantId('merchant-safeway');
      final merchant = Merchant(
        id: merchantId,
        name: 'Safeway',
        aliases: [
          MerchantAlias(
            id: MerchantAliasId('alias-safeway'),
            merchantId: merchantId,
            alias: 'Safeway Grocery',
            createdAt: at,
            updatedAt: at,
          ),
        ],
        normalizationPatterns: [
          MerchantNormalizationPattern(
            id: MerchantNormalizationPatternId('pattern-safeway'),
            merchantId: merchantId,
            pattern: 'Safeway Fuel',
            createdAt: at,
            updatedAt: at,
          ),
        ],
      );

      for (final evidence in [
        'SAFEWAY',
        'SAFEWAY GROCERY',
        'SAFEWAY FUEL #4',
      ]) {
        expect(
          synchronizeMerchantReviewIssue(
            _transaction(rawCounterparty: evidence),
            at,
            merchants: [merchant],
          ).reviewIssues,
          isEmpty,
        );
      }
    },
  );
}

Transaction _transaction({String? rawCounterparty, String? description}) =>
    Transaction(
      id: TransactionId('transaction-1'),
      timing: KnownTransactionTime(DateTime.utc(2026, 9, 1, 12)),
      money: Money(
        amount: DecimalValue.parse('12'),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.manual,
      transactionDate: '2026-09-01',
      description: description,
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
