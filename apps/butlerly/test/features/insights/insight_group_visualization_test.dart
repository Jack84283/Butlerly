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
  testWidgets('renders a donut from grouped category-share findings', (
    tester,
  ) async {
    final rule = AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R026'),
      version: RuleVersion('1.2.0'),
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
      role: 'neutral',
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
    InsightResult result(String dimension, String value) {
      final finding = AnalysisFinding(
        id: 'finding-$dimension',
        rule: rule,
        context: context,
        severity: RuleSeverity.info,
        lifecycle: FindingLifecycle.active,
        currentValue: DecimalValue.parse(value),
        dimension: dimension,
        generatedAt: DateTime.utc(2026, 9, 10),
      );
      return InsightResult(
        outputType: InsightOutputType.pattern,
        rule: rule,
        context: context,
        finding: finding,
        currentValue: finding.currentValue,
        currency: CurrencyCode('USD'),
        dimension: dimension,
      );
    }

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
        home: Scaffold(
          body: InsightGroupVisualizations(
            findings: [result('category.food', '50'), result('category.rent', '50')],
            masterData: const TransactionMasterData(
              categoryNames: {
                'category.food': 'Food',
                'category.rent': 'Rent',
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InsightDonutVisualization), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
  });
}
