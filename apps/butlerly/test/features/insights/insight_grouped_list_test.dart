import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/insights/presentation/insight_grouped_list.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'maps rule grouping to presentation section without semantic coupling',
    () {
      expect(
        insightPresentationGroup(
          _insight(
            RuleGrouping.transaction,
            semanticType: InsightSemanticType.attention,
          ),
        ),
        InsightPresentationGroup.unusual,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.transaction)),
        InsightPresentationGroup.other,
      );
      expect(
        insightPresentationGroup(
          _insight(
            RuleGrouping.transaction,
            semanticType: InsightSemanticType.positive,
          ),
        ),
        InsightPresentationGroup.other,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.category)),
        InsightPresentationGroup.category,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.subcategory)),
        InsightPresentationGroup.subcategory,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.tag)),
        InsightPresentationGroup.tag,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.merchant)),
        InsightPresentationGroup.merchant,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.paymentSource)),
        InsightPresentationGroup.paymentSource,
      );
      expect(
        insightPresentationGroup(_insight(RuleGrouping.none)),
        InsightPresentationGroup.other,
      );
    },
  );

  test(
    'uses authored presentation role for unusually large purchase section',
    () {
      expect(
        insightPresentationGroup(
          _insight(
            RuleGrouping.transaction,
            role: 'largePurchase',
            operation: RuleOperation.maximum,
            visualizationType: InsightVisualizationType.comparison,
            semanticType: InsightSemanticType.attention,
          ),
        ),
        InsightPresentationGroup.largePurchase,
      );
      expect(
        insightPresentationGroup(
          _insight(
            RuleGrouping.transaction,
            operation: RuleOperation.maximum,
            visualizationType: InsightVisualizationType.comparison,
            semanticType: InsightSemanticType.attention,
          ),
        ),
        InsightPresentationGroup.unusual,
      );
    },
  );

  testWidgets('Home counts the same visible Insight groups as device cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final summaries = insightGroupSummaries(context, [
              _insight(
                RuleGrouping.transaction,
                semanticType: InsightSemanticType.attention,
              ),
              _insight(
                RuleGrouping.transaction,
                semanticType: InsightSemanticType.attention,
              ),
              _insight(
                RuleGrouping.transaction,
                role: 'largePurchase',
                semanticType: InsightSemanticType.attention,
              ),
              _insight(RuleGrouping.category),
              _insight(RuleGrouping.merchant),
              _insight(
                RuleGrouping.paymentSource,
                visualizationType: InsightVisualizationType.pie,
              ),
            ]);
            expect(summaries.map((group) => group.group).toList(), [
              InsightPresentationGroup.unusual,
              InsightPresentationGroup.largePurchase,
              InsightPresentationGroup.category,
              InsightPresentationGroup.merchant,
            ]);
            expect(summaries.map((group) => group.count).toList(), [
              2,
              1,
              1,
              1,
            ]);
            expect(summaries.every((group) => group.title.isNotEmpty), isTrue);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('desktop insight groups render tables with drilldown', (
    tester,
  ) async {
    InsightResult? requested;
    final items = [
      _insight(
        RuleGrouping.transaction,
        semanticType: InsightSemanticType.attention,
        withComparison: true,
      ),
      _insight(
        RuleGrouping.transaction,
        role: 'largePurchase',
        semanticType: InsightSemanticType.attention,
      ),
      _insight(RuleGrouping.category, dimension: 'food', withComparison: true),
      _insight(RuleGrouping.subcategory, dimension: 'restaurants'),
      _insight(RuleGrouping.merchant, dimension: 'merchant-1'),
      _insight(RuleGrouping.none),
    ];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: InsightGroupedList(
              desktopGrid: true,
              results: items,
              masterData: const TransactionMasterData(
                categoryNames: {'food': 'Food', 'restaurants': 'Restaurants'},
                merchantNames: {'merchant-1': 'Corner Shop'},
              ),
              canViewTransactions: (_) => true,
              onViewTransactions: (insight) => requested = insight,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final group in [
      'unusual',
      'largePurchase',
      'category',
      'subcategory',
      'merchant',
      'other',
    ]) {
      expect(
        find.byKey(ValueKey('desktop-insights-table-$group')),
        findsOneWidget,
      );
    }
    expect(find.text('Previous period'), findsWidgets);
    expect(find.text('Current period'), findsWidgets);
    expect(find.text('Difference'), findsWidgets);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Restaurants'), findsOneWidget);
    expect(find.text('Corner Shop'), findsOneWidget);
    expect(find.text('5.00 USD'), findsWidgets);
    expect(find.text('10.00 USD'), findsWidgets);
    final action = find.descendant(
      of: find.byKey(const ValueKey('desktop-insight-row-category-0')),
      matching: find.byType(TextButton),
    );
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.tap(action);
    expect(requested?.dimension, 'food');
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow desktop insight cards scroll tables horizontally', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 460,
            child: InsightGroupedList(
              desktopGrid: true,
              results: [_insight(RuleGrouping.category, dimension: 'food')],
              masterData: const TransactionMasterData(
                categoryNames: {'food': 'Food'},
              ),
              canViewTransactions: (_) => false,
              onViewTransactions: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-insights-table-scroll-category')),
      findsOneWidget,
    );
    expect(find.text('Food'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device Insight groups retain their original list rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: InsightGroupedList(
            results: [_insight(RuleGrouping.category, dimension: 'food')],
            masterData: const TransactionMasterData(
              categoryNames: {'food': 'Food'},
            ),
            canViewTransactions: (_) => false,
            onViewTransactions: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-insights-table-category')),
      findsNothing,
    );
    expect(find.text('Food'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('recognizes an all-positive fallback group', () {
    expect(
      insightGroupIsPositiveOnly([
        _insight(RuleGrouping.none, semanticType: InsightSemanticType.positive),
        _insight(RuleGrouping.none, semanticType: InsightSemanticType.positive),
      ]),
      isTrue,
    );
    expect(
      insightGroupIsPositiveOnly([
        _insight(RuleGrouping.none, semanticType: InsightSemanticType.positive),
        _insight(
          RuleGrouping.none,
          semanticType: InsightSemanticType.attention,
        ),
      ]),
      isFalse,
    );
    expect(insightGroupIsPositiveOnly(const []), isFalse);
  });
}

InsightResult _insight(
  RuleGrouping grouping, {
  InsightSemanticType semanticType = InsightSemanticType.neutral,
  RuleOperation operation = RuleOperation.sum,
  InsightVisualizationType visualizationType = InsightVisualizationType.none,
  String? role,
  String? dimension,
  bool withComparison = false,
}) {
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
    identity: RuleIdentity('ANL-R999'),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.insight,
    nameKey: 'analysisSummary',
    descriptionKey: 'analysisSummary',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: RuleMeasure(
      operation: operation,
      field: 'amount',
      currencyBasis: CurrencyBasis.baseCurrency,
    ),
    grouping: grouping,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: const RuleCondition(operator: 'always'),
    severity: RuleSeverity.info,
    definitionHash: RuleDefinitionHash('9' * 64),
    surface: AnalysisSurface.insights,
    role: role,
    presentation: InsightPresentation(
      semanticType: semanticType,
      visualizationType: visualizationType,
      primaryMetric: InsightPrimaryMetric.amount,
    ),
  );
  return InsightResult(
    outputType: InsightOutputType.pattern,
    rule: rule,
    context: context,
    currentValue: DecimalValue.parse('10'),
    baselineValue: withComparison ? DecimalValue.parse('5') : null,
    absoluteChange: withComparison ? DecimalValue.parse('5') : null,
    percentageChange: withComparison ? DecimalValue.parse('100') : null,
    dimension: dimension,
    currency: CurrencyCode('USD'),
  );
}
