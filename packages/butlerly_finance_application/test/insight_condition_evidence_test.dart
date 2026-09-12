import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

const selectiveMarker = 'conditionEvidence:selective';

void main() {
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-09-01',
      endDate: '2026-09-05',
      timeZoneId: 'America/Los_Angeles',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    baseCurrency: CurrencyCode('USD'),
  );

  test('R024 unusual-transaction-only branch narrows evidence to current maximum', () {
    final result = const AnalysisRuleEngine().execute(
      dataset: AnalysisDataset(
        context: context,
        transactions: [
          _expense('current-high', '2026-09-01', '70'),
          _expense('current-low', '2026-09-02', '20'),
        ],
        baselineTransactions: [
          _expense('baseline-a', '2026-08-01', '40'),
          _expense('baseline-b', '2026-08-02', '40'),
        ],
      ),
      definitions: [_r024()],
    ).single;

    expect(result.finding, isNotNull);
    expect(
      result.finding!.evidence.map((value) => value.transactionId.value),
      ['current-high'],
    );
    expect(result.finding!.supportingMetrics, contains(selectiveMarker));
  });

  test('R024 period-increase branch keeps the full current population', () {
    final result = const AnalysisRuleEngine().execute(
      dataset: AnalysisDataset(
        context: context,
        transactions: [
          _expense('current-a', '2026-09-01', '60'),
          _expense('current-b', '2026-09-02', '40'),
        ],
        baselineTransactions: [
          _expense('baseline-a', '2026-08-01', '40'),
          _expense('baseline-b', '2026-08-02', '40'),
        ],
      ),
      definitions: [_r024()],
    ).single;

    expect(result.finding, isNotNull);
    expect(
      result.finding!.evidence.map((value) => value.transactionId.value).toSet(),
      {'current-a', 'current-b'},
    );
    expect(result.finding!.supportingMetrics, isNot(contains(selectiveMarker)));
  });

  test('R024 both matching branches keep criteria-style population evidence', () {
    final result = const AnalysisRuleEngine().execute(
      dataset: AnalysisDataset(
        context: context,
        transactions: [
          _expense('current-high', '2026-09-01', '80'),
          _expense('current-low', '2026-09-02', '30'),
        ],
        baselineTransactions: [
          _expense('baseline-a', '2026-08-01', '40'),
          _expense('baseline-b', '2026-08-02', '40'),
        ],
      ),
      definitions: [_r024()],
    ).single;

    expect(result.finding, isNotNull);
    expect(
      result.finding!.evidence.map((value) => value.transactionId.value).toSet(),
      {'current-high', 'current-low'},
    );
    expect(result.finding!.supportingMetrics, isNot(contains(selectiveMarker)));
  });
}

AnalysisRuleDefinition _r024() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R024'),
  version: RuleVersion('1.3.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.insight,
  nameKey: 'analysis.rule.r024.name',
  descriptionKey: 'analysis.rule.r024.description',
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
  condition: RuleCondition(
    operator: 'any',
    children: [
      RuleCondition(
        operator: 'all',
        children: [
          RuleCondition(
            operator: 'gt',
            left: 'currentTotal',
            value: DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0),
          ),
          RuleCondition(
            operator: 'gteMultiplier',
            left: 'currentTotal',
            right: 'baselineTotal',
            value: DecimalValue.parse('1.20'),
          ),
        ],
      ),
      RuleCondition(
        operator: 'gtMultiplier',
        left: 'currentMaximum',
        right: 'baselineAverage',
        value: DecimalValue.parse('1.50'),
      ),
    ],
  ),
  severity: RuleSeverity.attention,
  surface: AnalysisSurface.insights,
  filters: const [
    AnalysisFilter(
      kind: AnalysisFilterKind.direction,
      values: ['expense'],
    ),
  ],
  definitionHash: RuleDefinitionHash('2' * 64),
  resultPersistence: ResultPersistencePolicy.finding,
  refreshPolicy: RefreshPolicy.onInvalidation,
  outputType: InsightOutputType.alert,
);

AnalysisEconomicTransaction _expense(String id, String date, String amount) =>
    AnalysisEconomicTransaction(
      id: TransactionId(id),
      money: Money(
        amount: DecimalValue.parse(amount),
        currency: CurrencyCode('USD'),
      ),
      direction: TransactionDirection.expense,
      transactionDate: date,
    );
