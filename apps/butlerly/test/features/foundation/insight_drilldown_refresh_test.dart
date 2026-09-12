import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

const selectiveMarker = 'conditionEvidence:selective';

void main() {
  test('still-selective Insight refreshes exact transaction IDs', () {
    final decision = resolveInsightDrillDownRefresh(
      _evaluation([
        _insight(
          ruleId: 'ANL-R024',
          supportingMetrics: const [selectiveMarker],
          evidenceIds: const ['new-large-expense'],
        ),
      ]),
      ruleId: 'ANL-R024',
    );

    expect(decision.forceNoResults, isFalse);
    expect(decision.transactionIds, ['new-large-expense']);
  });

  test('Insight that no longer qualifies produces an empty locked result', () {
    final decision = resolveInsightDrillDownRefresh(
      _evaluation(const []),
      ruleId: 'ANL-R024',
    );

    expect(decision.forceNoResults, isTrue);
    expect(decision.transactionIds, isNull);
  });

  test('Insight switching to aggregate branch clears frozen evidence IDs', () {
    final decision = resolveInsightDrillDownRefresh(
      _evaluation([
        _insight(
          ruleId: 'ANL-R024',
          evidenceIds: const ['old-large-expense', 'another-expense'],
        ),
      ]),
      ruleId: 'ANL-R024',
    );

    expect(decision.forceNoResults, isFalse);
    expect(decision.transactionIds, isNull);
  });

  test('matching dimension is preserved when refreshing grouped Insights', () {
    final decision = resolveInsightDrillDownRefresh(
      _evaluation([
        _insight(
          ruleId: 'ANL-R024',
          dimension: 'category.dining',
          supportingMetrics: const [selectiveMarker],
          evidenceIds: const ['dining-expense'],
        ),
        _insight(
          ruleId: 'ANL-R024',
          dimension: 'category.travel',
          supportingMetrics: const [selectiveMarker],
          evidenceIds: const ['travel-expense'],
        ),
      ]),
      ruleId: 'ANL-R024',
      dimension: 'category.travel',
    );

    expect(decision.transactionIds, ['travel-expense']);
  });
}

InsightsEvaluation _evaluation(List<InsightResult> results) => InsightsEvaluation(
  summary: PeriodSummary(
    context: _context(),
    currency: CurrencyCode('USD'),
    comparisonAvailable: true,
  ),
  results: results,
  hasSufficientHistory: true,
);

InsightResult _insight({
  required String ruleId,
  String? dimension,
  List<String> supportingMetrics = const [],
  List<String> evidenceIds = const [],
}) {
  final rule = AnalysisRuleDefinition(
    identity: RuleIdentity(ruleId),
    version: RuleVersion('1.0.0'),
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
    grouping: dimension == null ? RuleGrouping.none : RuleGrouping.category,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: const RuleCondition(operator: 'gte'),
    severity: RuleSeverity.attention,
    surface: AnalysisSurface.insights,
    definitionHash: RuleDefinitionHash('d' * 64),
  );
  final evidence = evidenceIds
      .map((id) => EvidenceReference(transactionId: TransactionId(id)))
      .toList(growable: false);
  final finding = AnalysisFinding(
    id: '$ruleId-${dimension ?? 'overall'}',
    rule: rule,
    context: _context(),
    severity: RuleSeverity.attention,
    lifecycle: FindingLifecycle.active,
    currentValue: DecimalValue.parse('100'),
    baselineValue: DecimalValue.parse('80'),
    absoluteChange: DecimalValue.parse('20'),
    percentageChange: DecimalValue.parse('25'),
    dimension: dimension,
    supportingMetrics: supportingMetrics,
    evidence: evidence,
    generatedAt: DateTime.utc(2026, 9, 5),
  );
  return InsightResult(
    outputType: InsightOutputType.alert,
    rule: rule,
    context: _context(),
    finding: finding,
    currentValue: finding.currentValue,
    baselineValue: finding.baselineValue,
    absoluteChange: finding.absoluteChange,
    percentageChange: finding.percentageChange,
    currency: CurrencyCode('USD'),
    dimension: dimension,
    evidence: evidence,
  );
}

AnalysisContext _context() => AnalysisContext(
  period: AnalysisPeriod(
    startDate: '2026-09-01',
    endDate: '2026-09-05',
    timeZoneId: 'America/Los_Angeles',
  ),
  datasetMode: DatasetMode.allEligible,
  currencyBasis: CurrencyBasis.baseCurrency,
  baseCurrency: CurrencyCode('USD'),
);
