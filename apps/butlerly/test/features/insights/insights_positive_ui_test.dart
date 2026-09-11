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
  testWidgets('shows dedicated positive copy for savings improvement', (
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
      baseline: RuleBaseline.previousEquivalentPeriod,
      condition: RuleCondition(
        operator: 'gt',
        left: 'absoluteChange',
        value: DecimalValue.parse('0'),
      ),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('1' * 64),
      surface: AnalysisSurface.insights,
      role: 'positive',
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
      dimension: null,
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
    expect(find.text('Savings improved'), findsOneWidget);
    expect(
      find.text('Net savings improved compared with the previous equivalent period.'),
      findsOneWidget,
    );
    expect(find.byType(InsightComparisonVisualization), findsOneWidget);
    final visualization = tester.widget<InsightComparisonVisualization>(
      find.byType(InsightComparisonVisualization),
    );
    expect(visualization.signed, isTrue);
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
        home: const _LocalizedProbe(),
      ),
    );
    expect(find.text('积极变化'), findsOneWidget);
    expect(find.text('储蓄改善'), findsOneWidget);
  });
}

class _LocalizedProbe extends StatelessWidget {
  const _LocalizedProbe();

  @override
  Widget build(BuildContext context) {
    return const InsightsPage(
      loadEvaluation: null,
    );
  }
}
