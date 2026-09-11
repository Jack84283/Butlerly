import 'package:butlerly/features/insights/presentation/insight_presentation.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

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
  );

  AnalysisRuleDefinition rule({
    String id = 'ANL-R027',
    String? role,
    RuleGrouping grouping = RuleGrouping.none,
    RuleOperation operation = RuleOperation.sum,
    InsightOutputType outputType = InsightOutputType.pattern,
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
    measure: RuleMeasure(
      operation: operation,
      field: 'amount',
      currencyBasis: CurrencyBasis.baseCurrency,
    ),
    grouping: grouping,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: const RuleCondition(operator: 'none'),
    severity: RuleSeverity.info,
    definitionHash: RuleDefinitionHash('9' * 64),
    surface: AnalysisSurface.insights,
    role: role,
    outputType: outputType,
  );

  InsightResult result(
    AnalysisRuleDefinition definition, {
    DecimalValue? baseline,
  }) => InsightResult(
    outputType: definition.outputType,
    rule: definition,
    context: context,
    currentValue: DecimalValue.parse('80'),
    baselineValue: baseline,
    absoluteChange: baseline == null ? null : DecimalValue.parse('-20'),
    percentageChange: baseline == null ? null : DecimalValue.parse('-20'),
    currency: CurrencyCode('USD'),
  );

  test('positive role maps to positive semantic comparison presentation', () {
    final presentation = result(
      rule(role: 'positive'),
      baseline: DecimalValue.parse('100'),
    ).presentation;

    expect(presentation.semanticType, InsightSemanticType.positive);
    expect(
      presentation.visualizationType,
      InsightVisualizationType.comparison,
    );
    expect(presentation.primaryMetric, InsightPrimaryMetric.amount);
  });

  test('alert output defaults to attention without rule-id branching', () {
    final presentation = result(
      rule(id: 'ANL-R777', outputType: InsightOutputType.alert),
    ).presentation;

    expect(presentation.semanticType, InsightSemanticType.attention);
  });

  test('category share result maps to pie presentation', () {
    final presentation = result(
      rule(
        id: 'ANL-R778',
        grouping: RuleGrouping.category,
        operation: RuleOperation.share,
      ),
    ).presentation;

    expect(presentation.semanticType, InsightSemanticType.neutral);
    expect(presentation.visualizationType, InsightVisualizationType.pie);
    expect(presentation.primaryMetric, InsightPrimaryMetric.share);
  });
}
