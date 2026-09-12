import 'package:butlerly/features/insights/presentation/insight_grouped_list.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps rule grouping to presentation section without semantic coupling', () {
    expect(
      insightPresentationGroup(
        _insight(
          RuleGrouping.transaction,
          semanticType: InsightSemanticType.attention,
        ),
      ),
      InsightPresentationGroup.unusual,
    );
    expect(
      insightPresentationGroup(_insight(RuleGrouping.transaction)),
      InsightPresentationGroup.other,
    );
    expect(
      insightPresentationGroup(
        _insight(
          RuleGrouping.transaction,
          semanticType: InsightSemanticType.positive,
        ),
      ),
      InsightPresentationGroup.other,
    );
    expect(
      insightPresentationGroup(_insight(RuleGrouping.category)),
      InsightPresentationGroup.category,
    );
    expect(
      insightPresentationGroup(_insight(RuleGrouping.subcategory)),
      InsightPresentationGroup.subcategory,
    );
    expect(
      insightPresentationGroup(_insight(RuleGrouping.tag)),
      InsightPresentationGroup.tag,
    );
    expect(
      insightPresentationGroup(_insight(RuleGrouping.merchant)),
      InsightPresentationGroup.merchant,
    );
    expect(
      insightPresentationGroup(_insight(RuleGrouping.paymentSource)),
      InsightPresentationGroup.paymentSource,
    );
    expect(
      insightPresentationGroup(_insight(RuleGrouping.none)),
      InsightPresentationGroup.other,
    );
  });

  test('recognizes an all-positive fallback group', () {
    expect(
      insightGroupIsPositiveOnly([
        _insight(
          RuleGrouping.none,
          semanticType: InsightSemanticType.positive,
        ),
        _insight(
          RuleGrouping.none,
          semanticType: InsightSemanticType.positive,
        ),
      ]),
      isTrue,
    );
    expect(
      insightGroupIsPositiveOnly([
        _insight(
          RuleGrouping.none,
          semanticType: InsightSemanticType.positive,
        ),
        _insight(
          RuleGrouping.none,
          semanticType: InsightSemanticType.attention,
        ),
      ]),
      isFalse,
    );
    expect(insightGroupIsPositiveOnly(const []), isFalse);
  });
}

InsightResult _insight(
  RuleGrouping grouping, {
  InsightSemanticType semanticType = InsightSemanticType.neutral,
}) {
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
  final rule = AnalysisRuleDefinition(
    identity: RuleIdentity('ANL-R999'),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.insight,
    nameKey: 'analysisSummary',
    descriptionKey: 'analysisSummary',
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
    severity: RuleSeverity.info,
    definitionHash: RuleDefinitionHash('9' * 64),
    surface: AnalysisSurface.insights,
    presentation: InsightPresentationMetadata(
      semanticType: semanticType,
      visualizationType: InsightVisualizationType.none,
      primaryMetric: InsightPrimaryMetric.amount,
    ),
  );
  return InsightResult(
    outputType: InsightOutputType.pattern,
    rule: rule,
    context: context,
    currentValue: DecimalValue.parse('10'),
    currency: CurrencyCode('USD'),
  );
}
