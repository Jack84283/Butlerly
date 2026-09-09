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

    expect(find.text('Spending compared with baseline'), findsOneWidget);
    expect(find.textContaining('previous equivalent period'), findsOneWidget);
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

  testWidgets('renders multiple active insight rules generically', (
    tester,
  ) async {
    final results = <RuleExecutionResult>[
      _result(finding: _finding()),
      _result(
        rule: _syntheticRule(),
        finding: _finding(id: 'finding-2', rule: _syntheticRule()),
      ),
    ];
    await tester.pumpWidget(
      app((_) async => ApplicationSuccess<List<RuleExecutionResult>>(results)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Spending compared with baseline'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.byTooltip('Dismiss'), findsNWidgets(2));
  });

  testWidgets('renders only active findings in deterministic severity order', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        (_) async => ApplicationSuccess<List<RuleExecutionResult>>([
          _result(
            rule: _syntheticRule(),
            finding: _finding(
              id: 'info-finding',
              rule: _syntheticRule(),
              severity: RuleSeverity.info,
            ),
          ),
          _result(
            finding: _finding(
              id: 'critical-finding',
              severity: RuleSeverity.critical,
            ),
          ),
          _result(
            finding: _finding(
              id: 'dismissed-finding',
              lifecycle: FindingLifecycle.dismissed,
            ),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Dismiss'), findsNWidgets(2));
    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(
      titles.indexOf('Spending compared with baseline'),
      lessThan(titles.indexOf('Expenses')),
    );
  });

  test('supports authored insight copy in all V1 locales', () {
    expect(
      AppLocalizations(
        const Locale('en'),
      ).text('analysis.rule.r020.description'),
      'Compare spending in the selected period with the previous equivalent period.',
    );
    expect(
      AppLocalizations(
        const Locale('zh', 'CN'),
      ).text('analysis.rule.r020.description'),
      '将所选期间的支出与上一等效期间进行比较。',
    );
    expect(
      AppLocalizations(
        const Locale('es'),
      ).text('analysis.rule.r020.description'),
      'Compara los gastos del período seleccionado con el período equivalente anterior.',
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
  AnalysisRuleDefinition? rule,
}) => RuleExecutionResult(
  rule: rule ?? _rule(),
  finding: finding,
  comparison: comparison,
);

AnalysisFinding _finding({
  String id = 'finding-1',
  AnalysisRuleDefinition? rule,
  List<EvidenceReference> evidence = const [],
  RuleSeverity severity = RuleSeverity.attention,
  FindingLifecycle lifecycle = FindingLifecycle.active,
}) => AnalysisFinding(
  id: id,
  rule: rule ?? _rule(),
  context: _context(),
  severity: severity,
  lifecycle: lifecycle,
  currentValue: DecimalValue.parse('7420'),
  baselineValue: DecimalValue.parse('5930'),
  absoluteChange: DecimalValue.parse('1490'),
  percentageChange: DecimalValue.parse('25.1'),
  evidence: evidence,
  generatedAt: DateTime.utc(2026, 9, 5),
);

AnalysisRuleDefinition _syntheticRule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R999'),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.insight,
  nameKey: 'analysis.rule.r001.name',
  descriptionKey: 'analysis.rule.r020.description',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
  grouping: RuleGrouping.none,
  baseline: RuleBaseline.previousEquivalentPeriod,
  condition: const RuleCondition(operator: 'none'),
  severity: RuleSeverity.info,
  definitionHash: RuleDefinitionHash('e' * 64),
  surface: AnalysisSurface.insights,
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
