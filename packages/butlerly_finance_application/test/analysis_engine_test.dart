import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-01-01',
      endDate: '2026-01-31',
      timeZoneId: 'Asia/Shanghai',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.original,
  );
  AnalysisRuleDefinition rule(
    String id,
    RuleOperation operation, {
    List<RuleDependency> dependencies = const [],
    List<AnalysisFilter> filters = const [],
    RuleGrouping grouping = RuleGrouping.none,
  }) => AnalysisRuleDefinition(
    identity: RuleIdentity(id),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.metric,
    nameKey: 'name',
    descriptionKey: 'description',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'currentPeriod',
    measure: RuleMeasure(operation: operation, field: 'amount'),
    grouping: grouping,
    baseline: RuleBaseline.none,
    condition: const RuleCondition(operator: 'none'),
    severity: RuleSeverity.info,
    dependencies: dependencies,
    filters: filters,
    definitionHash: RuleDefinitionHash(
      '0000000000000000000000000000000000000000000000000000000000000000',
    ),
  );
  AnalysisDataset dataset() => AnalysisDataset(
    context: context,
    transactions: [
      AnalysisEconomicTransaction(
        id: TransactionId('t1'),
        money: Money(
          amount: DecimalValue.parse('10'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        transactionDate: '2026-01-02',
      ),
      AnalysisEconomicTransaction(
        id: TransactionId('t2'),
        money: Money(
          amount: DecimalValue.parse('25'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.income,
        transactionDate: '2026-01-03',
      ),
    ],
  );

  test('applies direction filters and exact decimal sums', () {
    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(),
      definitions: [
        rule(
          'ANL-R001',
          RuleOperation.sum,
          filters: [
            AnalysisFilter(
              kind: AnalysisFilterKind.direction,
              values: ['expense'],
            ),
          ],
        ),
      ],
    );
    expect(result.single.metric!.value, DecimalValue.parse('10'));
  });

  test('executes declared dependencies before difference', () {
    final expense = rule(
      'ANL-R001',
      RuleOperation.sum,
      filters: [
        AnalysisFilter(kind: AnalysisFilterKind.direction, values: ['expense']),
      ],
    );
    final income = rule(
      'ANL-R002',
      RuleOperation.sum,
      filters: [
        AnalysisFilter(kind: AnalysisFilterKind.direction, values: ['income']),
      ],
    );
    final net = rule(
      'ANL-R003',
      RuleOperation.difference,
      dependencies: [
        RuleDependency(ruleId: RuleIdentity('ANL-R001')),
        RuleDependency(ruleId: RuleIdentity('ANL-R002')),
      ],
    );
    final result = const AnalysisRuleEngine().execute(
      dataset: dataset(),
      definitions: [net, income, expense],
    );
    expect(result.last.metric!.value, DecimalValue.parse('15'));
  });
}
