import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/features/insights/presentation/insights_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only supporting-transactions action triggers insight drill-down', (
    tester,
  ) async {
    final context = _context();
    final rule = _rule('ANL-R020');
    final finding = _finding(rule, context, evidenceIds: const ['support-1']);
    final evaluation = _evaluation([
      _result(rule, context, finding),
    ]);
    String? navigation;

    await tester.pumpWidget(_app(evaluation, (path) => navigation = path));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spending compared with baseline'));
    await tester.pump();
    expect(navigation, isNull);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View 1 supporting transaction'));
    expect(
      navigation,
      '/search?locked=true&from=2026-09-01&to=2026-09-05',
    );
  });

  testWidgets(
    'R020 presentation keeps R024 selective evidence and drill-down context',
    (tester) async {
      final context = _context();
      final baselineRule = _rule('ANL-R020');
      final materialRule = _rule('ANL-R024');
      final baselineFinding = _finding(baselineRule, context);
      final materialFinding = _finding(
        materialRule,
        context,
        evidenceIds: const ['large-expense'],
        supportingMetrics: const ['conditionEvidence:selective'],
      );
      final evaluation = _evaluation([
        _result(baselineRule, context, baselineFinding),
        _result(materialRule, context, materialFinding),
      ]);
      String? navigation;

      await tester.pumpWidget(_app(evaluation, (path) => navigation = path));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('Spending compared with baseline'), findsOneWidget);
      expect(find.text('Material spending alert'), findsNothing);
      expect(find.text('View 1 supporting transaction'), findsOneWidget);

      await tester.tap(find.text('View 1 supporting transaction'));
      expect(
        navigation,
        '/search?locked=true&from=2026-09-01&to=2026-09-05&ids=large-expense&insightRule=ANL-R024',
      );
    },
  );
}

Widget _app(InsightsEvaluation evaluation, ValueChanged<String> onNavigation) =>
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
        onNavigationRequested: onNavigation,
      ),
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

AnalysisRuleDefinition _rule(String id) => AnalysisRuleDefinition(
  identity: RuleIdentity(id),
  version: RuleVersion('1.5.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.insight,
  nameKey: id == 'ANL-R024'
      ? 'analysis.rule.r024.name'
      : 'analysis.rule.r020.name',
  descriptionKey: id == 'ANL-R024'
      ? 'analysis.rule.r024.description'
      : 'analysis.rule.r020.description',
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
  definitionHash: RuleDefinitionHash(id == 'ANL-R024' ? 'b' * 64 : 'a' * 64),
  surface: AnalysisSurface.insights,
  filters: const [
    AnalysisFilter(
      kind: AnalysisFilterKind.direction,
      values: ['expense'],
    ),
  ],
  presentation: const InsightPresentation(
    semanticType: InsightSemanticType.attention,
    visualizationType: InsightVisualizationType.comparison,
    primaryMetric: InsightPrimaryMetric.amount,
  ),
);

AnalysisFinding _finding(
  AnalysisRuleDefinition rule,
  AnalysisContext context, {
  List<String> evidenceIds = const [],
  List<String> supportingMetrics = const [],
}) => AnalysisFinding(
  id: '${rule.identity.value}-finding',
  rule: rule,
  context: context,
  severity: RuleSeverity.attention,
  lifecycle: FindingLifecycle.active,
  currentValue: DecimalValue.parse('120'),
  baselineValue: DecimalValue.parse('80'),
  absoluteChange: DecimalValue.parse('40'),
  percentageChange: DecimalValue.parse('50'),
  supportingMetrics: supportingMetrics,
  evidence: evidenceIds
      .map(
        (id) => EvidenceReference(transactionId: TransactionId(id)),
      )
      .toList(growable: false),
  generatedAt: DateTime.utc(2026, 9, 5),
);

InsightResult _result(
  AnalysisRuleDefinition rule,
  AnalysisContext context,
  AnalysisFinding finding,
) => InsightResult(
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
);

InsightsEvaluation _evaluation(List<InsightResult> results) => InsightsEvaluation(
  summary: PeriodSummary(
    context: results.first.context,
    comparisonAvailable: true,
    currency: CurrencyCode('USD'),
  ),
  results: results,
  hasSufficientHistory: true,
);
