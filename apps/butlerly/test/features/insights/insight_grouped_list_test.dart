import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
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
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
      _insight(
        RuleGrouping.category,
        dimension: 'food',
        withComparison: true,
        evidence: [
          EvidenceReference(transactionId: TransactionId('support-1')),
          EvidenceReference(transactionId: TransactionId('support-2')),
          EvidenceReference(transactionId: TransactionId('support-3')),
        ],
      ),
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

    final groups = [
      'unusual',
      'largePurchase',
      'category',
      'subcategory',
      'merchant',
      'other',
    ];
    double? precedingTop;
    double? firstLeft;
    double? firstWidth;
    for (final group in groups) {
      final table = find.byKey(ValueKey('desktop-insights-table-$group'));
      expect(table, findsOneWidget);
      final top = tester.getTopLeft(table).dy;
      final left = tester.getTopLeft(table).dx;
      final width = tester.getSize(table).width;
      if (precedingTop != null) expect(top, greaterThan(precedingTop));
      if (firstLeft != null) expect(left, closeTo(firstLeft, 0.1));
      if (firstWidth != null) expect(width, closeTo(firstWidth, 0.1));
      precedingTop = top;
      firstLeft ??= left;
      firstWidth ??= width;
      expect(
        find.byKey(ValueKey('desktop-insights-table-scroll-$group')),
        findsNothing,
      );
    }
    // The former two-column grid constrained a card to half this width.
    expect(firstWidth!, greaterThan(1000));

    // Match the shared desktop transaction table: 12px padding on all sides,
    // not the 4px responsive padding used by the device inner cards.
    final categoryTable = find.byKey(
      const ValueKey('desktop-insights-table-category'),
    );
    final innerCard = find.ancestor(
      of: categoryTable,
      matching: find.byType(ButlerlyDesktopInnerCard),
    );
    expect(innerCard, findsOneWidget);
    final tableRect = tester.getRect(categoryTable);
    final innerRect = tester.getRect(innerCard);
    expect(
      tableRect.left - innerRect.left,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      innerRect.right - tableRect.right,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      tableRect.top - innerRect.top,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      innerRect.bottom - tableRect.bottom,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );

    // The first two columns flex equally. Three fixed-width columns keep
    // full labels visible; header and cell boundaries must line up.
    final expectedWidths = <String, double>{
      'previousPeriod': 160,
      'currentPeriod': 160,
      'transactions': 152,
    };
    double? previousRight;
    double? flexibleWidth;
    for (final name in [
      'insights',
      'difference',
      'previousPeriod',
      'currentPeriod',
      'transactions',
    ]) {
      final headerColumn = find.byKey(
        ValueKey('desktop-insights-column-category-$name'),
      );
      final dataColumn = find.byKey(
        ValueKey('desktop-insights-cell-category-0-$name'),
      );
      expect(headerColumn, findsOneWidget);
      expect(dataColumn, findsOneWidget);
      final headerWidth = tester.getSize(headerColumn).width;
      final dataWidth = tester.getSize(dataColumn).width;
      expect(dataWidth, closeTo(headerWidth, 0.1));
      if (previousRight != null) {
        expect(tester.getTopLeft(headerColumn).dx, closeTo(previousRight, 0.1));
      }
      previousRight = tester.getTopRight(headerColumn).dx;
      if (expectedWidths[name] case final width?) {
        expect(headerWidth, closeTo(width, 0.1));
      } else {
        flexibleWidth ??= headerWidth;
        expect(headerWidth, closeTo(flexibleWidth, 0.1));
      }
    }

    // Desktop title/subtitle spacing is 12px; only cards with a subtitle
    // receive the gap. The device card header retains its default 4px.
    final cardHeader = find.byKey(
      const ValueKey('desktop-insights-card-header-category'),
    );
    final headerTexts = find.descendant(
      of: cardHeader,
      matching: find.byType(Text),
    );
    expect(headerTexts, findsNWidgets(2));
    final subtitleGap =
        tester.getTopLeft(headerTexts.at(1)).dy -
        tester.getBottomLeft(headerTexts.at(0)).dy;
    expect(subtitleGap, closeTo(ButlerlySpacing.small, 0.1));

    expect(find.text('Previous period'), findsWidgets);
    expect(find.text('Current period'), findsWidgets);
    expect(find.text('Difference'), findsWidgets);
    expect(find.text('Transactions'), findsWidgets);
    expect(find.text('View transactions'), findsNothing);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Restaurants'), findsOneWidget);
    expect(find.text('Corner Shop'), findsOneWidget);
    expect(find.text('5.00 USD'), findsWidgets);
    expect(find.text('10.00 USD'), findsWidgets);
    final row = find.byKey(const ValueKey('desktop-insight-row-category-0'));
    final countCell = find.byKey(
      const ValueKey('desktop-insights-cell-category-0-transactions'),
    );
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byType(TextButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: countCell, matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: countCell, matching: find.text('3.00')),
      findsNothing,
    );
    // A single-line category row uses compact padding and a smaller icon.
    // It is no taller than the Home/Transactions desktop table rows.
    expect(tester.getSize(row).height, lessThanOrEqualTo(40));
    final rowInkWell = tester.widget<InkWell>(row);
    expect(rowInkWell.onTap, isNotNull);
    await tester.ensureVisible(row);
    await tester.tap(row);
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
    final row = find.byKey(const ValueKey('desktop-insight-row-category-0'));
    expect(tester.widget<InkWell>(row).onTap, isNull);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('desktop-insights-cell-category-0-transactions'),
        ),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
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
  List<EvidenceReference> evidence = const [],
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
    evidence: evidence,
    currency: CurrencyCode('USD'),
  );
}
