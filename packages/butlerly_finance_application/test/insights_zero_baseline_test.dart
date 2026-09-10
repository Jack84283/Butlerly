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
  }) => AnalysisEconomicTransaction(
    id: TransactionId(id),
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
    transactionDate: date,
  );

  AnalysisRuleDefinition rule({
    required String id,
    required RuleOperation operation,
    required RuleCondition condition,
  }) => AnalysisRuleDefinition(
    identity: RuleIdentity(id),
    version: RuleVersion('1.1.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.insight,
    nameKey: 'analysis.rule.test.name',
    descriptionKey: 'analysis.rule.test.description',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: RuleMeasure(
      operation: operation,
      field: 'amount',
      currencyBasis: CurrencyBasis.baseCurrency,
    ),
    grouping: RuleGrouping.none,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: condition,
    severity: RuleSeverity.attention,
    surface: AnalysisSurface.insights,
    outputType: InsightOutputType.pattern,
    resultPersistence: ResultPersistencePolicy.finding,
    definitionHash: RuleDefinitionHash('7' * 64),
    filters: const [
      AnalysisFilter(
        kind: AnalysisFilterKind.direction,
        values: ['expense'],
      ),
    ],
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

  test('empty previous period is a zero baseline and comparison still runs', () {
    final current = [expense('current-1', '25')];
    final definition = rule(
      id: 'ANL-R020',
      operation: RuleOperation.sum,
      condition: RuleCondition(
        operator: 'gt',
        left: 'value',
        value: DecimalValue.parse('0'),
      ),
    );

    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(current, const []),
      definitions: [definition],
    ).single;

    expect(result.comparison, isNotNull);
    expect(result.comparison!.baselineValue, DecimalValue.parse('0'));
    expect(result.comparison!.absoluteChange, DecimalValue.parse('25'));
    expect(result.comparison!.percentageChange, isNull);
    expect(result.comparison!.availability, AnalysisDataAvailability.empty);
    expect(result.finding, isNotNull);
    expect(
      result.issues.map((issue) => issue.code),
      isNot(contains('missingBaseline')),
    );
  });

  test('R024 triggers on 20 percent total increase', () {
    final current = [expense('c1', '60'), expense('c2', '60')];
    final baseline = [
      expense('b1', '50', date: '2026-08-05'),
      expense('b2', '50', date: '2026-08-06'),
    ];
    final definition = rule(
      id: 'ANL-R024',
      operation: RuleOperation.sum,
      condition: RuleCondition(
        operator: 'any',
        children: [
          RuleCondition(
            operator: 'gteMultiplier',
            left: 'currentTotal',
            right: 'baselineTotal',
            value: DecimalValue.parse('1.20'),
          ),
          RuleCondition(
            operator: 'gtMultiplier',
            left: 'currentMaximum',
            right: 'baselineAverage',
            value: DecimalValue.parse('1.50'),
          ),
        ],
      ),
    );

    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(current, baseline),
      definitions: [definition],
    ).single;

    expect(result.finding, isNotNull);
    expect(result.finding!.currentValue, DecimalValue.parse('120'));
    expect(result.finding!.baselineValue, DecimalValue.parse('100'));
  });

  test('R024 triggers on a transaction above 1.5 times prior average', () {
    final current = [expense('c1', '80'), expense('c2', '10')];
    final baseline = [
      expense('b1', '50', date: '2026-08-05'),
      expense('b2', '50', date: '2026-08-06'),
    ];
    final definition = rule(
      id: 'ANL-R024',
      operation: RuleOperation.sum,
      condition: RuleCondition(
        operator: 'any',
        children: [
          RuleCondition(
            operator: 'gteMultiplier',
            left: 'currentTotal',
            right: 'baselineTotal',
            value: DecimalValue.parse('1.20'),
          ),
          RuleCondition(
            operator: 'gtMultiplier',
            left: 'currentMaximum',
            right: 'baselineAverage',
            value: DecimalValue.parse('1.50'),
          ),
        ],
      ),
    );

    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(current, baseline),
      definitions: [definition],
    ).single;

    expect(result.finding, isNotNull);
    expect(result.finding!.currentValue, DecimalValue.parse('90'));
    expect(result.finding!.baselineValue, DecimalValue.parse('100'));
  });

  test('R024 treats an empty previous period as zero', () {
    final current = [expense('c1', '10')];
    final definition = rule(
      id: 'ANL-R024',
      operation: RuleOperation.sum,
      condition: RuleCondition(
        operator: 'any',
        children: [
          RuleCondition(
            operator: 'gteMultiplier',
            left: 'currentTotal',
            right: 'baselineTotal',
            value: DecimalValue.parse('1.20'),
          ),
          RuleCondition(
            operator: 'gtMultiplier',
            left: 'currentMaximum',
            right: 'baselineAverage',
            value: DecimalValue.parse('1.50'),
          ),
        ],
      ),
    );

    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(current, const []),
      definitions: [definition],
    ).single;

    expect(result.finding, isNotNull);
    expect(result.finding!.baselineValue, DecimalValue.parse('0'));
    expect(result.finding!.percentageChange, isNull);
  });

  test('R025 triggers above 3x previous average or 2x previous maximum', () {
    final current = [expense('c1', '310')];
    final baseline = [
      expense('b1', '40', date: '2026-08-05'),
      expense('b2', '100', date: '2026-08-06'),
    ];
    final definition = rule(
      id: 'ANL-R025',
      operation: RuleOperation.maximum,
      condition: RuleCondition(
        operator: 'any',
        children: [
          RuleCondition(
            operator: 'gtMultiplier',
            left: 'currentMaximum',
            right: 'baselineAverage',
            value: DecimalValue.parse('3.00'),
          ),
          RuleCondition(
            operator: 'gtMultiplier',
            left: 'currentMaximum',
            right: 'baselineMaximum',
            value: DecimalValue.parse('2.00'),
          ),
        ],
      ),
    );

    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(current, baseline),
      definitions: [definition],
    ).single;

    expect(result.finding, isNotNull);
    expect(result.finding!.currentValue, DecimalValue.parse('310'));
    expect(result.finding!.evidence.single.transactionId.value, 'c1');
  });

  test('R025 also evaluates against zero when previous period is empty', () {
    final current = [expense('c1', '1')];
    final definition = rule(
      id: 'ANL-R025',
      operation: RuleOperation.maximum,
      condition: RuleCondition(
        operator: 'any',
        children: [
          RuleCondition(
            operator: 'gtMultiplier',
            left: 'currentMaximum',
            right: 'baselineAverage',
            value: DecimalValue.parse('3.00'),
          ),
          RuleCondition(
            operator: 'gtMultiplier',
            left: 'currentMaximum',
            right: 'baselineMaximum',
            value: DecimalValue.parse('2.00'),
          ),
        ],
      ),
    );

    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(current, const []),
      definitions: [definition],
    ).single;

    expect(result.finding, isNotNull);
    expect(result.finding!.baselineValue, DecimalValue.parse('0'));
    expect(
      result.issues.map((issue) => issue.code),
      isNot(contains('missingBaseline')),
    );
  });
}
