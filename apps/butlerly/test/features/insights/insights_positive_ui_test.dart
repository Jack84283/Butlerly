import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/features/insights/presentation/insight_visualization.dart';
import 'package:butlerly/features/insights/presentation/insights_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows positive savings result in grouped presentation', (
    tester,
  ) async {
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R029'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.insight,
      nameKey: 'analysis.rule.r029.name',
      descriptionKey: 'analysis.rule.r029.description',
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
      definitionHash: RuleDefinitionHash('1' * 64),
      surface: AnalysisSurface.insights,
      presentation: const InsightPresentation(
        semanticType: InsightSemanticType.positive,
        visualizationType: InsightVisualizationType.comparison,
        primaryMetric: InsightPrimaryMetric.amount,
      ),
    );
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
    final finding = AnalysisFinding(
      id: 'saving-improvement',
      rule: rule,
      context: context,
      severity: RuleSeverity.info,
      lifecycle: FindingLifecycle.active,
      currentValue: DecimalValue.parse('500'),
      baselineValue: DecimalValue.parse('-250'),
      absoluteChange: DecimalValue.parse('750'),
      generatedAt: DateTime.utc(2026, 9, 10),
    );
    final evaluation = InsightsEvaluation(
      summary: PeriodSummary(
        context: context,
        currency: CurrencyCode('USD'),
        comparisonAvailable: true,
      ),
      results: [
        InsightResult(
          outputType: InsightOutputType.pattern,
          rule: rule,
          context: context,
          finding: finding,
          currentValue: finding.currentValue,
          baselineValue: finding.baselineValue,
          absoluteChange: finding.absoluteChange,
          currency: CurrencyCode('USD'),
        ),
      ],
      hasSufficientHistory: true,
    );

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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Positive changes'), findsOneWidget);
    expect(find.text('Other insights'), findsNothing);
    expect(find.text('Savings improved'), findsOneWidget);
    expect(
      find.text(
        'Net savings improved compared with the previous equivalent period.',
      ),
      findsOneWidget,
    );
    expect(find.text('500 USD'), findsOneWidget);
    expect(find.text('↔'), findsOneWidget);
    expect(find.text('vs'), findsNothing);
    expect(find.text('-250 USD'), findsOneWidget);
    expect(find.byIcon(Icons.trending_down), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.textContaining('2026-09-01 – 2026-09-10'), findsOneWidget);
  });

  testWidgets('keeps bar visualizations in the grouped presentation', (
    tester,
  ) async {
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
      identity: RuleIdentity('ANL-R998'),
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
      grouping: RuleGrouping.category,
      baseline: RuleBaseline.previousEquivalentPeriod,
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('8' * 64),
      surface: AnalysisSurface.insights,
      presentation: const InsightPresentation(
        semanticType: InsightSemanticType.neutral,
        visualizationType: InsightVisualizationType.bar,
        primaryMetric: InsightPrimaryMetric.amount,
      ),
    );
    final finding = AnalysisFinding(
      id: 'category-pattern',
      rule: rule,
      context: context,
      severity: RuleSeverity.info,
      lifecycle: FindingLifecycle.active,
      currentValue: DecimalValue.parse('100'),
      generatedAt: DateTime.utc(2026, 9, 10),
    );
    final evaluation = InsightsEvaluation(
      summary: PeriodSummary(
        context: context,
        currency: CurrencyCode('USD'),
        comparisonAvailable: true,
      ),
      results: [
        InsightResult(
          outputType: InsightOutputType.pattern,
          rule: rule,
          context: context,
          finding: finding,
          dimension: 'food',
          currentValue: DecimalValue.parse('100'),
          currency: CurrencyCode('USD'),
        ),
        InsightResult(
          outputType: InsightOutputType.pattern,
          rule: rule,
          context: context,
          dimension: 'travel',
          currentValue: DecimalValue.parse('200'),
          currency: CurrencyCode('USD'),
        ),
      ],
      hasSufficientHistory: true,
    );

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
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Categories'), findsOneWidget);
    expect(find.byType(InsightBarVisualization), findsOneWidget);
  });

  testWidgets('positive insight copy is localized in Chinese', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: _LocalizedProbe()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('积极变化'), findsOneWidget);
    expect(find.text('储蓄改善'), findsOneWidget);
  });

  test('new insight strings participate in localization completeness checks', () {
    const keys = {
      'insightsPositiveChanges',
      'analysis.rule.r027.name',
      'analysis.rule.r027.description',
      'analysis.rule.r028.name',
      'analysis.rule.r028.description',
      'analysis.rule.r029.name',
      'analysis.rule.r029.description',
    };
    for (final language in ['es', 'zh']) {
      final missing = AppLocalizations.missingKeysFor(language);
      for (final key in keys) {
        expect(missing, isNot(contains(key)));
      }
    }
  });
}

class _LocalizedProbe extends StatelessWidget {
  const _LocalizedProbe();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(context.l10n.text('insightsPositiveChanges')),
      Text(context.l10n.text('analysis.rule.r029.name')),
    ],
  );
}
