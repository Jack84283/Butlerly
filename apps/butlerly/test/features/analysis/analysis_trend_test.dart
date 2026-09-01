import 'package:butlerly/features/analysis/presentation/analysis_model.dart';
import 'package:butlerly/features/analysis/presentation/widgets/analysis_trend.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('zero trend points show the insufficient-data state', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const []));
    expect(
      find.text('More activity is needed to show a trend.'),
      findsOneWidget,
    );
  });

  testWidgets('one trend point remains visible and accessible', (tester) async {
    await tester.pumpWidget(_app([_metric('2026-01-02', '10')]));
    expect(find.bySemanticsLabel(RegExp('2026-01-02')), findsOneWidget);
  });

  testWidgets('multiple trend points expose the ordered time series', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([_metric('2026-01-02', '10'), _metric('2026-01-03', '25')]),
    );
    expect(
      find.bySemanticsLabel(RegExp('2026-01-02.*2026-01-03', dotAll: true)),
      findsOneWidget,
    );
  });
}

Widget _app(List<AnalysisMetric> trend) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: AnalysisTrend(
    model: AnalysisModel(
      trend: trend,
      categories: const [],
      insightUnavailable: false,
      qualityCount: 0,
      qualityEvaluated: false,
      qualityLimited: false,
    ),
    masterData: null,
  ),
);

AnalysisMetric _metric(String date, String value) {
  final rule = AnalysisRuleDefinition(
    identity: RuleIdentity('ANL-R014'),
    version: RuleVersion('1.3.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.metric,
    nameKey: 'analysis.rule.r014.name',
    descriptionKey: 'analysis.rule.r014.description',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
    grouping: RuleGrouping.day,
    baseline: RuleBaseline.none,
    condition: const RuleCondition(operator: 'none'),
    severity: RuleSeverity.info,
    definitionHash: RuleDefinitionHash('1' * 64),
  );
  return AnalysisMetric(
    id: 'trend-$date',
    rule: rule,
    context: AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-01-01',
        endDate: '2026-01-31',
        timeZoneId: 'UTC',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
      baseCurrency: CurrencyCode('USD'),
    ),
    value: DecimalValue.parse(value),
    dimension: '$date:sum',
    currency: CurrencyCode('USD'),
    calculatedAt: DateTime.utc(2026),
  );
}
