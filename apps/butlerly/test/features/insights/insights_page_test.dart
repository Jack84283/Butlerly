import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/insights/presentation/insights_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app<T>(
    Future<ApplicationResult<T>> Function(String) load, {
    ValueChanged<String>? onNavigationRequested,
    TransactionMasterData? masterData,
  }) {
    Future<ApplicationResult<InsightsEvaluation>> loadEvaluation(
      String period,
    ) async {
      final result = await load(period);
      if (result is ApplicationFailure<T>) {
        return ApplicationFailure(result.failure);
      }
      final value = (result as ApplicationSuccess<T>).value;
      if (value is InsightsEvaluation) return ApplicationSuccess(value);
      return ApplicationSuccess(
        _evaluation(value as List<RuleExecutionResult>),
      );
    }

    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: InsightsPage(
        key: UniqueKey(),
        loadEvaluation: loadEvaluation,
        onNavigationRequested: onNavigationRequested,
        masterData: masterData,
      ),
    );
  }

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
    expect(find.byTooltip('Dismiss'), findsNothing);
  });

  testWidgets(
    'always shows selected-period summary without an active finding',
    (tester) async {
      await tester.pumpWidget(
        app(
          (_) async => ApplicationSuccess(
            InsightsEvaluation(
              summary: PeriodSummary(
                context: _context(),
                expenseSpending: DecimalValue.parse('120'),
                income: DecimalValue.parse('300'),
                netCashFlow: DecimalValue.parse('180'),
                eligibleTransactionCount: 3,
                currency: CurrencyCode('USD'),
                comparisonAvailable: false,
              ),
              results: const [],
              hasSufficientHistory: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Period summary'), findsOneWidget);
      expect(find.text('Total spending'), findsOneWidget);
      expect(find.textContaining('120'), findsOneWidget);
      await tester.dragFrom(const Offset(400, 500), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Nothing needs your attention'), findsOneWidget);
    },
  );

  testWidgets('drills into locked search for supporting transactions', (
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
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View transactions'));
    expect(
      path,
      '/search?locked=true&from=2026-09-01&to=2026-09-05&ids=support-1%2Csupport-2',
    );
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
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Spending compared with baseline'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.byTooltip('Dismiss'), findsNothing);
  });

  testWidgets(
    'resolves and renders labels for multiple findings in one group',
    (tester) async {
      final rule = _groupedRule();
      await tester.pumpWidget(
        app(
          (_) async => ApplicationSuccess<List<RuleExecutionResult>>([
            _result(
              rule: rule,
              finding: _finding(
                id: 'food-finding',
                rule: rule,
                dimension: 'category.food',
              ),
            ),
            _result(
              rule: rule,
              finding: _finding(
                id: 'travel-finding',
                rule: rule,
                dimension: 'category.travel',
              ),
            ),
          ]),
          masterData: const TransactionMasterData(
            categoryNames: {
              'category.food': 'Food & Dining',
              'category.travel': 'Travel',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('Travel'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Category movement: Food & Dining'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Category movement: Travel'),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders only active findings in deterministic severity order', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        (_) async => ApplicationSuccess<List<RuleExecutionResult>>([
          _result(
            finding: _finding(
              id: 'critical-finding',
              severity: RuleSeverity.critical,
            ),
          ),
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
              id: 'dismissed-finding',
              lifecycle: FindingLifecycle.dismissed,
            ),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Dismiss'), findsNothing);
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

  testWidgets('renders subcategory and merchant grouping labels', (
    tester,
  ) async {
    final subcategoryRule = _groupedRule(
      id: 'ANL-R022',
      grouping: RuleGrouping.subcategory,
      nameKey: 'analysis.rule.r022.name',
      descriptionKey: 'analysis.rule.r022.description',
    );
    final merchantRule = _groupedRule(
      id: 'ANL-R023',
      grouping: RuleGrouping.merchant,
      nameKey: 'analysis.rule.r023.name',
      descriptionKey: 'analysis.rule.r023.description',
    );
    await tester.pumpWidget(
      app(
        (_) async => ApplicationSuccess<List<RuleExecutionResult>>([
          _result(
            rule: subcategoryRule,
            finding: _finding(
              id: 'restaurant-finding',
              rule: subcategoryRule,
              dimension: 'subcategory.restaurants',
            ),
          ),
          _result(
            rule: merchantRule,
            finding: _finding(
              id: 'merchant-finding',
              rule: merchantRule,
              dimension: 'merchant.acme',
            ),
          ),
        ]),
        masterData: const TransactionMasterData(
          categoryNames: {'subcategory.restaurants': 'Restaurants'},
          merchantNames: {'merchant.acme': 'Acme Market'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Restaurants'), findsOneWidget);
    expect(find.text('Acme Market'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Subcategory movement: Restaurants'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Merchant movement: Acme Market'),
      findsOneWidget,
    );
    expect(find.text('subcategory.restaurants'), findsNothing);
    expect(find.text('merchant.acme'), findsNothing);
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
    await tester.dragFrom(const Offset(400, 500), const Offset(0, -500));
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
    await tester.dragFrom(const Offset(400, 500), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Nothing needs your attention'), findsOneWidget);
  });

  testWidgets('does not expose an insight dismissal control', (tester) async {
    await tester.pumpWidget(
      app((_) async => ApplicationSuccess([_result(finding: _finding())])),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Dismiss'), findsNothing);
    expect(find.text('Spending compared with baseline'), findsOneWidget);
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
  String? dimension,
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
  dimension: dimension,
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

AnalysisRuleDefinition _groupedRule({
  String id = 'ANL-R021',
  RuleGrouping grouping = RuleGrouping.category,
  String nameKey = 'analysis.rule.r021.name',
  String descriptionKey = 'analysis.rule.r021.description',
}) => AnalysisRuleDefinition(
  identity: RuleIdentity(id),
  version: RuleVersion('1.1.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.insight,
  nameKey: nameKey,
  descriptionKey: descriptionKey,
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
  grouping: grouping,
  baseline: RuleBaseline.previousEquivalentPeriod,
  condition: const RuleCondition(operator: 'gte'),
  severity: RuleSeverity.attention,
  definitionHash: RuleDefinitionHash('b' * 64),
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

InsightsEvaluation _evaluation(List<RuleExecutionResult> results) {
  final context = results
      .map((result) => result.finding?.context ?? result.metric?.context)
      .whereType<AnalysisContext>()
      .firstOrNull;
  final resolvedContext = context ?? _context();
  return InsightsEvaluation(
    summary: PeriodSummary(
      context: resolvedContext,
      currency: resolvedContext.baseCurrency,
      comparisonAvailable: results.any(
        (result) =>
            result.comparison?.availability ==
            AnalysisDataAvailability.sufficient,
      ),
      limitations: results
          .expand((result) => result.issues)
          .toList(growable: false),
    ),
    results: results
        .where(
          (result) =>
              result.rule.surface == AnalysisSurface.insights &&
              result.rule.type == AnalysisRuleType.insight,
        )
        .map(
          (result) => InsightResult(
            outputType: result.rule.outputType,
            rule: result.rule,
            context: resolvedContext,
            finding: result.finding,
            currentValue:
                result.finding?.currentValue ?? result.comparison?.currentValue,
            baselineValue:
                result.finding?.baselineValue ??
                result.comparison?.baselineValue,
            absoluteChange:
                result.finding?.absoluteChange ??
                result.comparison?.absoluteChange,
            percentageChange:
                result.finding?.percentageChange ??
                result.comparison?.percentageChange,
            currency: resolvedContext.baseCurrency,
            dimension: result.finding?.dimension,
            evidence: result.finding?.evidence ?? const [],
            limitations: result.issues,
            failure: result.failure,
          ),
        )
        .toList(growable: false),
    hasSufficientHistory: results.any(
      (result) =>
          result.finding != null ||
          result.metric != null ||
          result.comparison?.availability ==
              AnalysisDataAvailability.sufficient ||
          result.comparison?.availability == AnalysisDataAvailability.empty,
    ),
  );
}

DecimalValue _zero() =>
    DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0);
