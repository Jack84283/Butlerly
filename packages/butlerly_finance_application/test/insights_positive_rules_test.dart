import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-09-01',
      endDate: '2026-09-10',
      timeZoneId: 'America/Los_Angeles',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    baseCurrency: CurrencyCode('USD'),
    periodType: 'selected_period',
  );

  AnalysisEconomicTransaction expense(
    String id,
    String amount, {
    String date = '2026-09-05',
    String? categoryId,
  }) => AnalysisEconomicTransaction(
    id: TransactionId(id),
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode('USD'),
    ),
    normalizedMoney: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
    transactionDate: date,
    categoryId: categoryId == null ? null : CategoryId(categoryId),
  );

  AnalysisDataset dataset(
    List<AnalysisEconomicTransaction> current,
    List<AnalysisEconomicTransaction> baseline,
  ) => AnalysisDataset(
    context: context,
    transactions: current,
    primaryTransactionsByPeriod: {'selected_period': current},
    baselineTransactions: baseline,
    baselineTransactionsByPeriod: {'selected_period': baseline},
  );

  RuleCondition decreaseBy20Percent() => RuleCondition(
    operator: 'all',
    children: [
      RuleCondition(
        operator: 'gt',
        left: 'baselineTotal',
        value: DecimalValue.parse('0'),
      ),
      RuleCondition(
        operator: 'lte',
        left: 'percentageChange',
        value: DecimalValue.parse('-20'),
      ),
    ],
  );

  AnalysisRuleDefinition positiveRule({
    required String id,
    RuleGrouping grouping = RuleGrouping.none,
  }) => AnalysisRuleDefinition(
    identity: RuleIdentity(id),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.insight,
    nameKey: 'analysis.rule.test.name',
    descriptionKey: 'analysis.rule.test.description',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: const RuleMeasure(
      operation: RuleOperation.sum,
      field: 'amount',
      currencyBasis: CurrencyBasis.baseCurrency,
    ),
    grouping: grouping,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: decreaseBy20Percent(),
    severity: RuleSeverity.info,
    surface: AnalysisSurface.insights,
    outputType: InsightOutputType.pattern,
    resultPersistence: ResultPersistencePolicy.finding,
    definitionHash: RuleDefinitionHash('8' * 64),
    role: 'positive',
    filters: const [
      AnalysisFilter(
        kind: AnalysisFilterKind.direction,
        values: ['expense'],
      ),
    ],
  );

  test('overall spending decrease triggers at exactly 20 percent', () {
    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(
        [expense('current', '80')],
        [expense('baseline', '100', date: '2026-08-05')],
      ),
      definitions: [positiveRule(id: 'ANL-R027')],
    ).single;

    expect(result.finding, isNotNull);
    expect(result.finding!.currentValue, DecimalValue.parse('80'));
    expect(result.finding!.baselineValue, DecimalValue.parse('100'));
    expect(result.finding!.percentageChange, DecimalValue.parse('-20'));
  });

  test('overall spending decrease does not trigger below threshold', () {
    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(
        [expense('current', '81')],
        [expense('baseline', '100', date: '2026-08-05')],
      ),
      definitions: [positiveRule(id: 'ANL-R027')],
    ).single;

    expect(result.finding, isNull);
  });

  test('zero baseline is compared but is not classified as a decrease', () {
    final result = const AnalysisRuleEngine().execute(
      dataset: dataset([expense('current', '25')], const []),
      definitions: [positiveRule(id: 'ANL-R027')],
    ).single;

    expect(result.comparison!.baselineValue, DecimalValue.parse('0'));
    expect(result.comparison!.percentageChange, isNull);
    expect(result.finding, isNull);
  });

  test('category decrease evaluates each current category against its baseline', () {
    final results = const AnalysisRuleEngine().execute(
      dataset: dataset(
        [
          expense('food-current', '40', categoryId: 'food'),
          expense('travel-current', '90', categoryId: 'travel'),
        ],
        [
          expense(
            'food-baseline',
            '50',
            date: '2026-08-05',
            categoryId: 'food',
          ),
          expense(
            'travel-baseline',
            '100',
            date: '2026-08-06',
            categoryId: 'travel',
          ),
        ],
      ),
      definitions: [
        positiveRule(id: 'ANL-R028', grouping: RuleGrouping.category),
      ],
    );

    final byDimension = {
      for (final result in results) result.finding?.dimension ?? 'none': result,
    };
    expect(byDimension['food']?.finding, isNotNull);
    expect(
      results.where((result) => result.finding?.dimension == 'travel'),
      isEmpty,
    );
  });

  test('new category from zero is not classified as a spending decrease', () {
    final results = const AnalysisRuleEngine().execute(
      dataset: dataset(
        [expense('new-current', '20', categoryId: 'new-category')],
        [
          expense(
            'other-baseline',
            '100',
            date: '2026-08-05',
            categoryId: 'other-category',
          ),
        ],
      ),
      definitions: [
        positiveRule(id: 'ANL-R028', grouping: RuleGrouping.category),
      ],
    );

    expect(results.single.comparison!.baselineValue, DecimalValue.parse('0'));
    expect(results.single.finding, isNull);
  });
}
