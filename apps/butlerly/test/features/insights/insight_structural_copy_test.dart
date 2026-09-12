import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/insights/presentation/insight_grouped_list.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('one structural rule owns section title and description', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([
        _categoryInsight(
          id: 'ANL-R021',
          nameKey: 'analysis.rule.r021.name',
          descriptionKey: 'analysis.rule.r021.description',
          dimension: 'category.food',
        ),
        _categoryInsight(
          id: 'ANL-R021',
          nameKey: 'analysis.rule.r021.name',
          descriptionKey: 'analysis.rule.r021.description',
          dimension: 'category.travel',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Category movement'), findsOneWidget);
    expect(
      find.text(
        'A category changed materially compared with the equivalent period.',
      ),
      findsOneWidget,
    );
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
  });

  testWidgets('mixed structural rules retain their own rule meaning', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([
        _categoryInsight(
          id: 'ANL-R021',
          nameKey: 'analysis.rule.r021.name',
          descriptionKey: 'analysis.rule.r021.description',
          dimension: 'category.food',
        ),
        _categoryInsight(
          id: 'ANL-R026',
          nameKey: 'analysis.rule.r026.name',
          descriptionKey: 'analysis.rule.r026.description',
          dimension: 'category.travel',
          operation: RuleOperation.share,
          semanticType: InsightSemanticType.neutral,
          visualizationType: InsightVisualizationType.pie,
          primaryMetric: InsightPrimaryMetric.share,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Category movement'), findsOneWidget);
    expect(find.text('Spending concentration'), findsOneWidget);
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
  });
}

Widget _app(List<InsightResult> results) => MaterialApp(
  theme: ThemeData(extensions: const [ButlerlySemanticColors.light]),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: InsightGroupedList(
      results: results,
      masterData: const TransactionMasterData(
        categoryNames: {
          'category.food': 'Food & Dining',
          'category.travel': 'Travel',
        },
      ),
      canViewTransactions: (_) => false,
      onViewTransactions: (_) {},
    ),
  ),
);

InsightResult _categoryInsight({
  required String id,
  required String nameKey,
  required String descriptionKey,
  required String dimension,
  RuleOperation operation = RuleOperation.sum,
  InsightSemanticType semanticType = InsightSemanticType.attention,
  InsightVisualizationType visualizationType =
      InsightVisualizationType.comparison,
  InsightPrimaryMetric primaryMetric = InsightPrimaryMetric.amount,
}) {
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
  final rule = AnalysisRuleDefinition(
    identity: RuleIdentity(id),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.insight,
    nameKey: nameKey,
    descriptionKey: descriptionKey,
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: RuleMeasure(
      operation: operation,
      field: 'amount',
      currencyBasis: CurrencyBasis.baseCurrency,
    ),
    grouping: RuleGrouping.category,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: const RuleCondition(operator: 'always'),
    severity: RuleSeverity.attention,
    definitionHash: RuleDefinitionHash(id == 'ANL-R021' ? '1' * 64 : '2' * 64),
    surface: AnalysisSurface.insights,
    outputType: InsightOutputType.pattern,
    presentation: InsightPresentation(
      semanticType: semanticType,
      visualizationType: visualizationType,
      primaryMetric: primaryMetric,
    ),
  );
  return InsightResult(
    outputType: InsightOutputType.pattern,
    rule: rule,
    context: context,
    currentValue: DecimalValue.parse('120'),
    baselineValue: DecimalValue.parse('80'),
    absoluteChange: DecimalValue.parse('40'),
    percentageChange: DecimalValue.parse('50'),
    currency: CurrencyCode('USD'),
    dimension: dimension,
  );
}
