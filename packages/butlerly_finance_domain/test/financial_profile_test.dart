import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 28, 12);

  test('counts optional answers without requiring survey completion', () {
    final profile = FinancialProfile(
      householdSize: HouseholdSize.two,
      primarySpendingCategoryIds: const ['category.food'],
      hasMonthlySavingsTarget: false,
      preferredInsightTypes: const [
        FinancialInsightType.spendingTrends,
        FinancialInsightType.spendingTrends,
      ],
      createdAt: now,
      updatedAt: now,
    );

    expect(profile.answeredQuestionCount, 4);
    expect(profile.completionFraction, closeTo(4 / 11, 0.0001));
    expect(profile.preferredInsightTypes, [
      FinancialInsightType.spendingTrends,
    ]);
    expect(profile.createdAt, now);
  });

  test('preserves the savings target and currency relationship', () {
    final profile = FinancialProfile(
      monthlySavingsTarget: DecimalValue.parse('250.50'),
      hasMonthlySavingsTarget: true,
      monthlySavingsTargetCurrency: CurrencyCode('USD'),
      status: FinancialProfileStatus.completed,
      completedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    expect(profile.monthlySavingsTarget, DecimalValue.parse('250.50'));
    expect(profile.monthlySavingsTargetCurrency, CurrencyCode('USD'));
    expect(profile.status, FinancialProfileStatus.completed);
    expect(profile.completedAt, now);
  });

  test('rejects an incomplete savings target relationship', () {
    expect(
      () => FinancialProfile(
        monthlySavingsTarget: DecimalValue.parse('250'),
        createdAt: now,
        updatedAt: now,
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('limits primary spending categories to three unique identifiers', () {
    expect(
      () => FinancialProfile(
        primarySpendingCategoryIds: const ['a', 'b', 'c', 'd'],
        createdAt: now,
        updatedAt: now,
      ),
      throwsA(isA<DomainValidationException>()),
    );

    final profile = FinancialProfile(
      primarySpendingCategoryIds: const [' a ', 'a'],
      createdAt: now,
      updatedAt: now,
    );
    expect(profile.primarySpendingCategoryIds, ['a']);
  });
}
