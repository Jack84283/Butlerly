import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/features/insights/presentation/insights_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only View Transactions triggers insight drill-down', (tester) async {
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R020'),
      version: RuleVersion('1.5.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.insight,
      nameKey: 'analysis.rule.r020.name',
      descriptionKey: 'analysis.rule.r020.description',
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
      severity: RuleSeverity.attention,
      definitionHash: RuleDefinitionHash('a' * 64),
      surface: AnalysisSurface.insights,
      presentation: const InsightPresentation(
        semanticType: InsightSemanticType.attention,
        visualizationType: InsightVisualizationType.comparison,
        primaryMetric: InsightPrimaryMetric.amount,
      ),
    );
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
    final finding = AnalysisFinding(
      id: 'finding',
      rule: rule,
      context: context,
      severity: RuleSeverity.attention,
      lifecycle: FindingLifecycle.active,
      currentValue: DecimalValue.parse('120'),
      baselineValue: DecimalValue.parse('80'),
      absoluteChange: DecimalValue.parse('40'),
      percentageChange: DecimalValue.parse('50'),
      evidence: [
        EvidenceReference(transactionId: TransactionId('support-1')),
      ],
      generatedAt: DateTime.utc(2026, 9, 5),
    );
    final evaluation = InsightsEvaluation(
      summary: PeriodSummary(
        context: context,
        comparisonAvailable: true,
        currency: CurrencyCode('USD'),
      ),
      results: [
        InsightResult(
          outputType: InsightOutputType.alert,
          rule: rule,
          context: context,
          finding: finding,
          currentValue: finding.currentValue,
          baselineValue: finding.baselineValue,
          absoluteChange: finding.absoluteChange,
          percentageChange: finding.percentageChange,
          evidence: finding.evidence,
          currency: CurrencyCode('USD'),
        ),
      ],
      hasSufficientHistory: true,
    );
    String? navigation;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [ButlerlySemanticColors.light],
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: InsightsPage(
          loadEvaluation: (_) async => ApplicationSuccess(evaluation),
          onNavigationRequested: (path) => navigation = path,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spending compared with baseline'));
    await tester.pump();
    expect(navigation, isNull);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View transactions'));
    expect(
      navigation,
      '/search?locked=true&from=2026-09-01&to=2026-09-05&ids=support-1',
    );
  });
}
