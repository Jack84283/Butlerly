import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/insights/presentation/insight_group_visualization.dart';
import 'package:butlerly/features/insights/presentation/insight_visualization.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget testApp({
    required List<InsightResult> results,
    required TransactionMasterData masterData,
    Locale? locale,
  }) => MaterialApp(
    locale: locale,
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
    home: Scaffold(
      body: InsightGroupVisualizations(
        results: results,
        masterData: masterData,
      ),
    ),
  );

  AnalysisContext context() => AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-09-01',
      endDate: '2026-09-10',
      timeZoneId: 'America/Los_Angeles',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    baseCurrency: CurrencyCode('USD'),
  );

  testWidgets(
    'renders full category composition even when only one R026 finding triggers',
    (tester) async {
      final rule = AnalysisRuleDefinition(
        identity: RuleIdentity('ANL-R026'),
        version: RuleVersion('1.3.0'),
        schemaVersion: '1.0.0',
        type: AnalysisRuleType.insight,
        nameKey: 'analysis.rule.r026.name',
        descriptionKey: 'analysis.rule.r026.description',
        enabled: true,
        status: AnalysisRuleStatus.active,
        period: 'selected_period',
        measure: const RuleMeasure(
          operation: RuleOperation.share,
          field: 'amount',
          currencyBasis: CurrencyBasis.baseCurrency,
        ),
        grouping: RuleGrouping.category,
        baseline: RuleBaseline.none,
        condition: RuleCondition(
          operator: 'gte',
          left: 'value',
          value: DecimalValue.parse('50'),
        ),
        severity: RuleSeverity.info,
        definitionHash: RuleDefinitionHash('2' * 64),
        surface: AnalysisSurface.insights,
        presentation: const InsightPresentation(
          semanticType: InsightSemanticType.neutral,
          visualizationType: InsightVisualizationType.pie,
          primaryMetric: InsightPrimaryMetric.share,
        ),
      );
      final analysisContext = context();
      InsightResult result(
        String dimension,
        String value, {
        bool active = false,
      }) {
        final parsed = DecimalValue.parse(value);
        final finding = active
            ? AnalysisFinding(
                id: 'finding-$dimension',
                rule: rule,
                context: analysisContext,
                severity: RuleSeverity.info,
                lifecycle: FindingLifecycle.active,
                currentValue: parsed,
                dimension: dimension,
                generatedAt: DateTime.utc(2026, 9, 10),
              )
            : null;
        return InsightResult(
          outputType: InsightOutputType.pattern,
          rule: rule,
          context: analysisContext,
          finding: finding,
          currentValue: parsed,
          currency: CurrencyCode('USD'),
          dimension: active ? dimension : '$dimension:value',
        );
      }

      final results = [
        result('category.food', '60', active: true),
        result('category.rent', '25'),
        result('category.other', '15'),
      ];
      expect(results.where((result) => result.isActive), hasLength(1));

      await tester.pumpWidget(
        testApp(
          results: results,
          masterData: const TransactionMasterData(
            categoryNames: {
              'category.food': 'Food',
              'category.rent': 'Rent',
              'category.other': 'Other',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InsightDonutVisualization), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('60.00%'), findsOneWidget);
      expect(find.text('25.00%'), findsOneWidget);
      expect(find.text('15.00%'), findsOneWidget);
    },
  );

  testWidgets('uses locale-aware decimal separators in chart values', (
    tester,
  ) async {
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R099'),
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
      grouping: RuleGrouping.paymentSource,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('9' * 64),
      surface: AnalysisSurface.insights,
      presentation: const InsightPresentation(
        semanticType: InsightSemanticType.neutral,
        visualizationType: InsightVisualizationType.bar,
        primaryMetric: InsightPrimaryMetric.amount,
      ),
    );
    final analysisContext = context();
    InsightResult result(String dimension, String value) => InsightResult(
      outputType: InsightOutputType.pattern,
      rule: rule,
      context: analysisContext,
      currentValue: DecimalValue.parse(value),
      currency: CurrencyCode('USD'),
      dimension: '$dimension:value',
    );

    await tester.pumpWidget(
      testApp(
        locale: const Locale('es'),
        results: [
          result('source.visa', '1234.5'),
          result('source.cash', '30'),
        ],
        masterData: const TransactionMasterData(
          paymentSourceNames: {
            'source.visa': 'Personal Visa',
            'source.cash': 'Cash',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1.234,50'), findsOneWidget);
    expect(find.textContaining('30,00'), findsOneWidget);
  });

  testWidgets('resolves payment-source chart labels from master data', (
    tester,
  ) async {
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R099'),
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
      grouping: RuleGrouping.paymentSource,
      baseline: RuleBaseline.none,
      condition: const RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      definitionHash: RuleDefinitionHash('9' * 64),
      surface: AnalysisSurface.insights,
      presentation: const InsightPresentation(
        semanticType: InsightSemanticType.neutral,
        visualizationType: InsightVisualizationType.bar,
        primaryMetric: InsightPrimaryMetric.amount,
      ),
    );
    final analysisContext = context();
    InsightResult result(String dimension, String value) => InsightResult(
      outputType: InsightOutputType.pattern,
      rule: rule,
      context: analysisContext,
      currentValue: DecimalValue.parse(value),
      currency: CurrencyCode('USD'),
      dimension: '$dimension:value',
    );

    await tester.pumpWidget(
      testApp(
        results: [result('source.visa', '70'), result('source.cash', '30')],
        masterData: const TransactionMasterData(
          paymentSourceNames: {
            'source.visa': 'Personal Visa',
            'source.cash': 'Cash',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InsightBarVisualization), findsOneWidget);
    expect(find.text('Personal Visa'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Unavailable payment source'), findsNothing);
  });
}
