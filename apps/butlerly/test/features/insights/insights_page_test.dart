import 'package:butlerly/features/insights/presentation/insights_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(
    Future<ApplicationResult<List<RuleExecutionResult>>> Function(String)
    load, {
    Future<ApplicationResult<void>> Function(String)? dismissFinding,
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
      key: UniqueKey(),
      load: load,
      dismissFinding: dismissFinding,
      onNavigationRequested: onNavigationRequested,
    ),
  );

  testWidgets('shows an R020 finding with its comparison values', (
    tester,
  ) async {
    final finding = _finding();
    await tester.pumpWidget(
      app((_) async => ApplicationSuccess([_result(finding: finding)])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spending increased'), findsOneWidget);
    expect(
      find.textContaining('higher than the previous period'),
      findsOneWidget,
    );
    expect(find.textContaining('7,420'), findsOneWidget);
    expect(find.textContaining('5,930'), findsOneWidget);
    expect(find.textContaining('1,490'), findsOneWidget);
    expect(find.byTooltip('Dismiss'), findsOneWidget);
  });

  testWidgets('drills into the finding period for supporting transactions', (
    tester,
  ) async {
    String? path;
    await tester.pumpWidget(
      app(
        (_) async => ApplicationSuccess([
          _result(
            finding: _finding(
              evidence: [
                EvidenceReference(transactionId: TransactionId('support-1')),
                EvidenceReference(transactionId: TransactionId('support-2')),
              ],
            ),
          ),
        ]),
        onNavigationRequested: (value) => path = value,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View transactions'));
    expect(path, '/transactions?ids=support-1%2Csupport-2');
  });

  test('supports authored insight copy in all V1 locales', () {
    expect(
      AppLocalizations(const Locale('en')).text('insightSpendingIncreaseTitle'),
      'Spending increased',
    );
    expect(
      AppLocalizations(
        const Locale('zh', 'CN'),
      ).text('insightSpendingIncreaseTitle'),
      '支出增加',
    );
    expect(
      AppLocalizations(const Locale('es')).text('insightSpendingIncreaseTitle'),
      'Los gastos aumentaron',
    );
  });

  testWidgets('distinguishes insufficient history from no noteworthy insight', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        (_) async => ApplicationSuccess([
          _result(
            comparison: AnalysisComparison(
              currentValue: _zero(),
              availability: AnalysisDataAvailability.insufficient,
            ),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not enough history yet'), findsOneWidget);
    expect(find.text('Add data'), findsNothing);

    await tester.pumpWidget(
      app(
        (_) async => ApplicationSuccess([
          _result(
            comparison: AnalysisComparison(
              currentValue: _zero(),
              baselineValue: _zero(),
              absoluteChange: _zero(),
              percentageChange: _zero(),
              availability: AnalysisDataAvailability.sufficient,
            ),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing needs your attention'), findsOneWidget);
  });

  testWidgets('dismissal removes the active finding after success', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      app(
        (_) async => dismissed
            ? ApplicationSuccess([
                _result(
                  comparison: AnalysisComparison(
                    currentValue: _zero(),
                    baselineValue: _zero(),
                    absoluteChange: _zero(),
                    percentageChange: _zero(),
                    availability: AnalysisDataAvailability.sufficient,
                  ),
                ),
              ])
            : ApplicationSuccess([_result(finding: _finding())]),
        dismissFinding: (_) async {
          dismissed = true;
          return const ApplicationSuccess(null);
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing needs your attention'), findsOneWidget);
  });
}

RuleExecutionResult _result({
  AnalysisFinding? finding,
  AnalysisComparison? comparison,
}) => RuleExecutionResult(
  rule: _rule(),
  finding: finding,
  comparison: comparison,
);

AnalysisFinding _finding({List<EvidenceReference> evidence = const []}) =>
    AnalysisFinding(
      id: 'finding-1',
      rule: _rule(),
      context: _context(),
      severity: RuleSeverity.attention,
      lifecycle: FindingLifecycle.active,
      currentValue: DecimalValue.parse('7420'),
      baselineValue: DecimalValue.parse('5930'),
      absoluteChange: DecimalValue.parse('1490'),
      percentageChange: DecimalValue.parse('25.1'),
      evidence: evidence,
      generatedAt: DateTime.utc(2026, 9, 5),
    );

AnalysisRuleDefinition _rule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R020'),
  version: RuleVersion('1.2.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.insight,
  nameKey: 'analysis.rule.r020.name',
  descriptionKey: 'analysis.rule.r020.description',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
  grouping: RuleGrouping.none,
  baseline: RuleBaseline.previousEquivalentPeriod,
  condition: RuleCondition(
    operator: 'gte',
    value: DecimalValue.fromParts(coefficient: BigInt.from(20), scale: 0),
  ),
  severity: RuleSeverity.attention,
  definitionHash: RuleDefinitionHash('a' * 64),
  surface: AnalysisSurface.insights,
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

DecimalValue _zero() =>
    DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0);
