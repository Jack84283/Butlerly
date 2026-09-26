import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1, 12);

  test(
    'merchant matching values preserve source text and normalized values',
    () {
      final alias = MerchantAlias(
        id: MerchantAliasId('alias.costco'),
        merchantId: MerchantId('merchant.costco'),
        alias: 'Costco Store 1234',
        createdAt: now,
        updatedAt: now,
      );
      final pattern = MerchantNormalizationPattern(
        id: MerchantNormalizationPatternId('pattern.costco'),
        merchantId: MerchantId('merchant.costco'),
        pattern: 'COSTCO #1234',
        createdAt: now,
        updatedAt: now,
      );

      expect(alias.alias, 'Costco Store 1234');
      expect(alias.normalizedAlias, 'costco');
      expect(pattern.pattern, 'COSTCO #1234');
      expect(pattern.normalizedPattern, 'costco');
      expect(alias.archive(now).status, MerchantMatchingStatus.archived);
      expect(pattern.archive(now).status, MerchantMatchingStatus.archived);
    },
  );

  test(
    'transaction rules match supported conditions and apply assignments',
    () {
      final rule = TransactionRule(
        id: TransactionRuleId('rule.costco'),
        name: 'Classify Costco',
        merchantId: MerchantId('merchant.costco'),
        descriptionContains: 'fuel',
        assignCategoryId: CategoryId('category.transport'),
        assignTagId: TagId('tag.vehicle'),
        createdAt: now,
        updatedAt: now,
      );
      final transaction = Transaction(
        id: TransactionId('transaction.costco'),
        timing: KnownTransactionTime(now),
        money: Money(
          amount: DecimalValue.parse('25.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.import,
        provenance: [
          Provenance(
            id: ProvenanceId('provenance.costco'),
            sourceType: ProvenanceSourceType.import,
            capturedAt: now,
            originalRepresentation: 'COSTCO FUEL',
          ),
        ],
        createdAt: now,
        updatedAt: now,
        merchantId: MerchantId('merchant.costco'),
        description: 'Costco fuel',
        rawCounterparty: 'COSTCO FUEL',
      );

      expect(rule.matches(transaction), isTrue);
      final applied = rule.apply(
        transaction,
        now.add(const Duration(minutes: 1)),
      );
      expect(applied.categoryId, CategoryId('category.transport'));
      expect(applied.tagIds, contains(TagId('tag.vehicle')));
      expect(rule.disable(now).matches(transaction), isFalse);
    },
  );

  test('rules require at least one condition and one action', () {
    expect(
      () => TransactionRule(
        id: TransactionRuleId('rule.invalid'),
        name: 'Invalid',
        createdAt: now,
        updatedAt: now,
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });
}
