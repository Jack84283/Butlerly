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

  AnalysisEconomicTransaction transaction(
    String id,
    String amount,
    TransactionDirection direction, {
    String date = '2026-09-05',
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
    direction: direction,
    transactionDate: date,
  );

  AnalysisRuleDefinition totalRule({
    required String id,
    required String role,
    required TransactionDirection direction,
  }) => AnalysisRuleDefinition(
    identity: RuleIdentity(id),
    version: RuleVersion('1.3.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.metric,
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
    grouping: RuleGrouping.none,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: const RuleCondition(operator: 'none'),
    severity: RuleSeverity.info,
    surface: AnalysisSurface.overview,
    role: role,
    definitionHash: RuleDefinitionHash(
      id == 'ANL-R001' ? '1' * 64 : '2' * 64,
    ),
    filters: [
      AnalysisFilter(
        kind: AnalysisFilterKind.direction,
        values: [direction.name],
      ),
    ],
  );

  AnalysisRuleDefinition savingsRule() => AnalysisRuleDefinition(
    identity: RuleIdentity('ANL-R029'),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.insight,
    nameKey: 'analysis.rule.r003.name',
    descriptionKey: 'analysis.rule.r003.description',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: const RuleMeasure(
      operation: RuleOperation.difference,
      field: 'amount',
      currencyBasis: CurrencyBasis.baseCurrency,
    ),
    grouping: RuleGrouping.none,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: RuleCondition(
      operator: 'gt',
      left: 'absoluteChange',
      value: DecimalValue.parse('0'),
    ),
    severity: RuleSeverity.info,
    surface: AnalysisSurface.insights,
    role: 'positive',
    outputType: InsightOutputType.pattern,
    resultPersistence: ResultPersistencePolicy.finding,
    definitionHash: RuleDefinitionHash('3' * 64),
    dependencies: [
      RuleDependency(ruleId: RuleIdentity('ANL-R001')),
      RuleDependency(ruleId: RuleIdentity('ANL-R002')),
    ],
  );

  final definitions = [
    totalRule(
      id: 'ANL-R001',
      role: 'expenseTotal',
      direction: TransactionDirection.expense,
    ),
    totalRule(
      id: 'ANL-R002',
      role: 'incomeTotal',
      direction: TransactionDirection.income,
    ),
    savingsRule(),
  ];

  AnalysisDataset dataset({
    required String currentIncome,
    required String currentExpense,
    String? baselineIncome,
    String? baselineExpense,
  }) {
    final current = [
      transaction('current-income', currentIncome, TransactionDirection.income),
      transaction(
        'current-expense',
        currentExpense,
        TransactionDirection.expense,
      ),
    ];
    final baseline = baselineIncome == null || baselineExpense == null
        ? <AnalysisEconomicTransaction>[]
        : [
            transaction(
              'baseline-income',
              baselineIncome,
              TransactionDirection.income,
              date: '2026-08-05',
            ),
            transaction(
              'baseline-expense',
              baselineExpense,
              TransactionDirection.expense,
              date: '2026-08-06',
            ),
          ];
    return AnalysisDataset(
      context: context,
      transactions: current,
      primaryTransactionsByPeriod: {'selected_period': current},
      baselineTransactions: baseline,
      baselineTransactionsByPeriod: {'selected_period': baseline},
    );
  }

  RuleExecutionResult savingsResult(AnalysisDataset dataset) =>
      const AnalysisRuleEngine()
          .execute(dataset: dataset, definitions: definitions)
          .firstWhere((result) => result.rule.identity.value == 'ANL-R029');

  test('positive savings improvement triggers', () {
    final result = savingsResult(
      dataset(
        currentIncome: '1000',
        currentExpense: '700',
        baselineIncome: '1000',
        baselineExpense: '800',
      ),
    );

    expect(result.failure, isNull);
    expect(result.finding, isNotNull);
    expect(result.finding!.currentValue, DecimalValue.parse('300'));
    expect(result.finding!.baselineValue, DecimalValue.parse('200'));
    expect(result.finding!.absoluteChange, DecimalValue.parse('100'));
  });

  test('zero baseline to positive savings triggers without infinite percent', () {
    final result = savingsResult(
      dataset(
        currentIncome: '1000',
        currentExpense: '900',
        baselineIncome: '1000',
        baselineExpense: '1000',
      ),
    );

    expect(result.finding, isNotNull);
    expect(result.finding!.baselineValue, DecimalValue.parse('0'));
    expect(result.finding!.currentValue, DecimalValue.parse('100'));
    expect(result.finding!.percentageChange, isNull);
  });

  test('negative savings becoming less negative is an improvement', () {
    final result = savingsResult(
      dataset(
        currentIncome: '900',
        currentExpense: '1000',
        baselineIncome: '800',
        baselineExpense: '1000',
      ),
    );

    expect(result.finding, isNotNull);
    expect(result.finding!.baselineValue, DecimalValue.parse('-200'));
    expect(result.finding!.currentValue, DecimalValue.parse('-100'));
    expect(result.finding!.absoluteChange, DecimalValue.parse('100'));
  });

  test('negative savings crossing to positive is an improvement', () {
    final result = savingsResult(
      dataset(
        currentIncome: '1100',
        currentExpense: '1000',
        baselineIncome: '800',
        baselineExpense: '1000',
      ),
    );

    expect(result.finding, isNotNull);
    expect(result.finding!.baselineValue, DecimalValue.parse('-200'));
    expect(result.finding!.currentValue, DecimalValue.parse('100'));
    expect(result.finding!.absoluteChange, DecimalValue.parse('300'));
  });

  test('positive savings becoming negative does not trigger', () {
    final result = savingsResult(
      dataset(
        currentIncome: '900',
        currentExpense: '1000',
        baselineIncome: '1100',
        baselineExpense: '1000',
      ),
    );

    expect(result.finding, isNull);
    expect(result.comparison!.absoluteChange, DecimalValue.parse('-200'));
  });

  test('empty previous period is zero and positive savings still compares', () {
    final result = savingsResult(
      dataset(currentIncome: '500', currentExpense: '300'),
    );

    expect(result.failure, isNull);
    expect(result.comparison!.baselineValue, DecimalValue.parse('0'));
    expect(result.comparison!.percentageChange, isNull);
    expect(result.finding, isNotNull);
    expect(result.finding!.currentValue, DecimalValue.parse('200'));
  });
}
