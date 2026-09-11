import 'package:butlerly/features/insights/presentation/insights_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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

    await tester.tap(find.text('View transactions'));
    expect(
      path,
      '/search?locked=true&from=2026-09-01&to=2026-09-05&ids=support-1',
    );
  });
}

InsightResult _merchantInsight({List<EvidenceReference> evidence = const []}) {
  final context = _context();
  final rule = AnalysisRuleDefinition(
    identity: RuleIdentity('ANL-R023'),
    version: RuleVersion('1.1.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.insight,
    nameKey: 'analysis.rule.r023.name',
    descriptionKey: 'analysis.rule.r023.description',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
    grouping: RuleGrouping.merchant,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: const RuleCondition(operator: 'gte'),
    severity: RuleSeverity.attention,
    definitionHash: RuleDefinitionHash('c' * 64),
    surface: AnalysisSurface.insights,
  );
  final finding = AnalysisFinding(
    id: 'merchant-finding',
    rule: rule,
    context: context,
    severity: RuleSeverity.attention,
    lifecycle: FindingLifecycle.active,
    currentValue: DecimalValue.parse('200'),
    baselineValue: DecimalValue.parse('100'),
    absoluteChange: DecimalValue.parse('100'),
    percentageChange: DecimalValue.parse('100'),
    dimension: 'merchant.acme',
    evidence: evidence,
    generatedAt: DateTime.utc(2026, 9, 5),
  );
  return InsightResult(
    outputType: InsightOutputType.pattern,
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
