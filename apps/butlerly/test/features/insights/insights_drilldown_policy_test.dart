import 'package:butlerly/features/insights/presentation/insights_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const selectiveMarker = 'conditionEvidence:selective';

void main() {
  Widget app(
    InsightResult insight, {
    ValueChanged<String>? onNavigationRequested,
  }) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: InsightsPage(
      loadEvaluation: (_) async => ApplicationSuccess(_evaluation(insight)),
      onNavigationRequested: onNavigationRequested,
    ),
  );

  testWidgets('does not offer imprecise merchant drill-down without evidence', (
    tester,
  ) async {
    await tester.pumpWidget(app(_merchantInsight()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('View transactions'), findsNothing);
  });

  testWidgets('offers exact merchant drill-down when evidence IDs exist', (
    tester,
  ) async {
    String? path;
    await tester.pumpWidget(
      app(
        _merchantInsight(
          evidence: [
            EvidenceReference(transactionId: TransactionId('support-1')),
          ],
        ),
        onNavigationRequested: (value) => path = value,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('1 supporting transaction'));
    expect(
      path,
      '/search?locked=true&from=2026-09-01&to=2026-09-05&ids=support-1',
    );
  });

  testWidgets('category drill-down uses live criteria instead of evidence IDs', (
    tester,
  ) async {
    String? path;
    await tester.pumpWidget(
      app(
        _categoryInsight(
          'category.dining',
          evidence: [
            EvidenceReference(transactionId: TransactionId('old-support')),
          ],
          filters: const [
            AnalysisFilter(
              kind: AnalysisFilterKind.direction,
              values: ['expense'],
            ),
          ],
        ),
        onNavigationRequested: (value) => path = value,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('1 supporting transaction'));
    expect(
      path,
      '/search?locked=true&from=2026-09-01&to=2026-09-05&direction=expense&category=category.dining',
    );
    expect(path, isNot(contains('ids=')));
  });

  testWidgets('overall spending drill-down carries the expense rule filter', (
    tester,
  ) async {
    String? path;
    await tester.pumpWidget(
      app(
        _overallInsight(
          evidence: [
            EvidenceReference(transactionId: TransactionId('old-support')),
          ],
        ),
        onNavigationRequested: (value) => path = value,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('1 supporting transaction'));
    expect(
      path,
      '/search?locked=true&from=2026-09-01&to=2026-09-05&direction=expense',
    );
    expect(path, isNot(contains('ids=')));
  });

  testWidgets('selective R024 branch drills into evidence and carries refresh context', (
    tester,
  ) async {
    String? path;
    await tester.pumpWidget(
      app(
        _selectiveOverallInsight(
          evidence: [
            EvidenceReference(transactionId: TransactionId('large-expense')),
          ],
        ),
        onNavigationRequested: (value) => path = value,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('1 supporting transaction'));
    expect(
      path,
      '/search?locked=true&from=2026-09-01&to=2026-09-05&direction=expense&ids=large-expense&insightRule=ANL-R024',
    );
  });

  testWidgets('multi-value filters fall back to exact evidence without throwing', (
    tester,
  ) async {
    String? path;
    await tester.pumpWidget(
      app(
        _insight(
          grouping: RuleGrouping.none,
          dimension: null,
          ruleId: 'ANL-R024',
          nameKey: 'analysis.rule.r024.name',
          descriptionKey: 'analysis.rule.r024.description',
          outputType: InsightOutputType.alert,
          evidence: [
            EvidenceReference(transactionId: TransactionId('support-1')),
          ],
          filters: const [
            AnalysisFilter(
              kind: AnalysisFilterKind.direction,
              values: ['expense', 'income'],
            ),
          ],
        ),
        onNavigationRequested: (value) => path = value,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('1 supporting transaction'));
    expect(
      path,
      '/search?locked=true&from=2026-09-01&to=2026-09-05&ids=support-1',
    );
  });

  testWidgets('offers precise uncategorized category drill-down', (
    tester,
  ) async {
    String? path;
    await tester.pumpWidget(
      app(
        _categoryInsight('uncategorized'),
        onNavigationRequested: (value) => path = value,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View transactions'));
    expect(
      path,
      '/search?locked=true&from=2026-09-01&to=2026-09-05&uncategorized=true',
    );
  });
}

InsightResult _merchantInsight({List<EvidenceReference> evidence = const []}) =>
    _insight(
      grouping: RuleGrouping.merchant,
      dimension: 'merchant.acme',
      ruleId: 'ANL-R023',
      nameKey: 'analysis.rule.r023.name',
      descriptionKey: 'analysis.rule.r023.description',
      evidence: evidence,
    );

InsightResult _categoryInsight(
  String dimension, {
  List<EvidenceReference> evidence = const [],
  List<AnalysisFilter> filters = const [],
}) => _insight(
  grouping: RuleGrouping.category,
  dimension: dimension,
  ruleId: 'ANL-R021',
  nameKey: 'analysis.rule.r021.name',
  descriptionKey: 'analysis.rule.r021.description',
  evidence: evidence,
  filters: filters,
);

InsightResult _overallInsight({List<EvidenceReference> evidence = const []}) =>
    _insight(
      grouping: RuleGrouping.none,
      dimension: null,
      ruleId: 'ANL-R020',
      nameKey: 'analysis.rule.r020.name',
      descriptionKey: 'analysis.rule.r020.description',
      evidence: evidence,
      filters: const [
        AnalysisFilter(
          kind: AnalysisFilterKind.direction,
          values: ['expense'],
        ),
      ],
    );

InsightResult _selectiveOverallInsight({
  List<EvidenceReference> evidence = const [],
}) => _insight(
  grouping: RuleGrouping.none,
  dimension: null,
  ruleId: 'ANL-R024',
  nameKey: 'analysis.rule.r024.name',
  descriptionKey: 'analysis.rule.r024.description',
  outputType: InsightOutputType.alert,
  evidence: evidence,
  supportingMetrics: const [selectiveMarker],
  filters: const [
    AnalysisFilter(
      kind: AnalysisFilterKind.direction,
      values: ['expense'],
    ),
  ],
);

InsightResult _insight({
  required RuleGrouping grouping,
  required String? dimension,
  required String ruleId,
  required String nameKey,
  required String descriptionKey,
  InsightOutputType outputType = InsightOutputType.pattern,
  List<EvidenceReference> evidence = const [],
  List<AnalysisFilter> filters = const [],
  List<String> supportingMetrics = const [],
}) {
  final context = _context();
  final rule = AnalysisRuleDefinition(
    identity: RuleIdentity(ruleId),
    version: RuleVersion('1.1.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.insight,
    nameKey: nameKey,
    descriptionKey: descriptionKey,
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
    grouping: grouping,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: const RuleCondition(operator: 'gte'),
    severity: RuleSeverity.attention,
    definitionHash: RuleDefinitionHash('c' * 64),
    surface: AnalysisSurface.insights,
    filters: filters,
  );
  final finding = AnalysisFinding(
    id: '$ruleId-finding',
    rule: rule,
    context: context,
    severity: RuleSeverity.attention,
    lifecycle: FindingLifecycle.active,
    currentValue: DecimalValue.parse('200'),
    baselineValue: DecimalValue.parse('100'),
    absoluteChange: DecimalValue.parse('100'),
    percentageChange: DecimalValue.parse('100'),
    dimension: dimension,
    supportingMetrics: supportingMetrics,
    evidence: evidence,
    generatedAt: DateTime.utc(2026, 9, 5),
  );
  return InsightResult(
    outputType: outputType,
    rule: rule,
    context: context,
    finding: finding,
    currentValue: finding.currentValue,
    baselineValue: finding.baselineValue,
    absoluteChange: finding.absoluteChange,
    percentageChange: finding.percentageChange,
    currency: context.baseCurrency,
    dimension: finding.dimension,
    evidence: evidence,
    limitations: const [],
  );
}

InsightsEvaluation _evaluation(InsightResult insight) => InsightsEvaluation(
  summary: PeriodSummary(
    context: insight.context,
    currency: insight.context.baseCurrency,
    comparisonAvailable: true,
  ),
  results: [insight],
  hasSufficientHistory: true,
);

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
