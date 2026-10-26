import 'package:butlerly/features/budgets/application/monthly_budget_actuals.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Budget budget(String scope, String? scopeId, {String currency = 'USD'}) =>
      Budget(
        id: 'budget-1',
        scope: scope,
        scopeId: scopeId,
        currency: currency,
        amount: '100.00',
      );

  AnalysisMetric metric(
    String value, {
    String? dimension,
    RuleGrouping grouping = RuleGrouping.none,
    AnalysisDataAvailability availability = AnalysisDataAvailability.sufficient,
    String currency = 'USD',
  }) {
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R701'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'monthlySpending',
      descriptionKey: 'monthlySpending',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(
        operation: RuleOperation.sum,
        field: 'amount',
      ),
      grouping: grouping,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('a' * 64),
      role: AnalysisSemanticRole.expenseTotal,
      surface: AnalysisSurface.spending,
    );
    return AnalysisMetric(
      id: 'metric-1',
      rule: rule,
      context: AnalysisContext(
        period: AnalysisPeriod(
          startDate: '2026-10-01',
          endDate: '2026-10-31',
          timeZoneId: 'UTC',
        ),
        datasetMode: DatasetMode.allEligible,
        currencyBasis: CurrencyBasis.baseCurrency,
        baseCurrency: CurrencyCode(currency),
      ),
      value: DecimalValue.parse(value),
      currency: CurrencyCode(currency),
      dimension: dimension,
      calculatedAt: DateTime.utc(2026, 10, 26),
      availability: availability,
    );
  }

  final overall = metric('190.00');

  test('merchant ID matches analysis dimension with measure suffix', () {
    final matched = metric(
      '62.50',
      dimension: 'merchant-uuid-123:amount',
      grouping: RuleGrouping.merchant,
    );
    final actual = resolveMonthlyBudgetActual(
      budget('merchant', 'merchant-uuid-123'),
      AnalysisOverview(spending: overall, merchants: [matched]),
    );
    expect(actual.spent, 62.5);
    expect(actual.metric, same(matched));
  });

  test('subcategory ID matches analysis dimension with measure suffix', () {
    final matched = metric(
      '23.75',
      dimension: 'subcategory-uuid-4:amount',
      grouping: RuleGrouping.subcategory,
    );
    final actual = resolveMonthlyBudgetActual(
      budget('subcategory', 'subcategory-uuid-4'),
      AnalysisOverview(spending: overall, subcategories: [matched]),
    );
    expect(actual.spent, 23.75);
    expect(actual.metric, same(matched));
  });

  test('new merchant without monthly transactions shows zero spending', () {
    final other = metric(
      '85.00',
      dimension: 'some-other-merchant:amount',
      grouping: RuleGrouping.merchant,
    );
    final actual = resolveMonthlyBudgetActual(
      budget('merchant', 'new-merchant'),
      AnalysisOverview(spending: overall, merchants: [other]),
    );
    expect(actual.spent, 0);
    expect(actual.metric, isNull);
  });

  test('missing category and subcategory groups show zero spending', () {
    const overview = AnalysisOverview();
    for (final scope in ['category', 'subcategory']) {
      expect(
        resolveMonthlyBudgetActual(
          budget(scope, 'new-scope-id'),
          AnalysisOverview(spending: overall),
        ).spent,
        0,
      );
      expect(
        resolveMonthlyBudgetActual(
          budget(scope, 'new-scope-id'),
          overview,
        ).spent,
        isNull,
      );
    }
  });

  test('empty monthly metric is zero, not an error', () {
    final empty = metric(
      '0',
      dimension: 'merchant-new:amount',
      grouping: RuleGrouping.merchant,
      availability: AnalysisDataAvailability.empty,
    );
    final actual = resolveMonthlyBudgetActual(
      budget('merchant', 'merchant-new'),
      AnalysisOverview(spending: overall, merchants: [empty]),
    );
    expect(actual.spent, 0);
    expect(actual.metric, same(empty));
  });

  test('no valid overall analysis means missing merchant is unavailable', () {
    final actual = resolveMonthlyBudgetActual(
      budget('merchant', 'new-merchant'),
      const AnalysisOverview(),
    );
    expect(actual.spent, isNull);
    expect(actual.metric, isNull);
  });

  test('insufficient analysis must never be displayed as zero', () {
    final unavailable = metric(
      '0',
      availability: AnalysisDataAvailability.insufficient,
    );
    expect(
      resolveMonthlyBudgetActual(
        budget('merchant', 'new-merchant'),
        AnalysisOverview(spending: unavailable),
      ).spent,
      isNull,
    );
    final badGroup = metric(
      '90.00',
      dimension: 'merchant-new:amount',
      grouping: RuleGrouping.merchant,
      availability: AnalysisDataAvailability.insufficient,
    );
    expect(
      resolveMonthlyBudgetActual(
        budget('merchant', 'merchant-new'),
        AnalysisOverview(spending: overall, merchants: [badGroup]),
      ).spent,
      isNull,
    );
  });

  test('currency mismatch must never show spending or fabricated zero', () {
    expect(
      resolveMonthlyBudgetActual(
        budget('merchant', 'new-merchant', currency: 'EUR'),
        AnalysisOverview(spending: overall),
      ).spent,
      isNull,
    );
    final group = metric(
      '15.00',
      dimension: 'merchant-new:amount',
      grouping: RuleGrouping.merchant,
    );
    expect(
      resolveMonthlyBudgetActual(
        budget('merchant', 'merchant-new', currency: 'EUR'),
        AnalysisOverview(spending: overall, merchants: [group]),
      ).spent,
      isNull,
    );
  });

  test('overall budget still uses the canonical spending metric', () {
    final actual = resolveMonthlyBudgetActual(
      budget('overall', null),
      AnalysisOverview(spending: overall),
    );
    expect(actual.spent, 190);
    expect(actual.metric, same(overall));
  });
}
